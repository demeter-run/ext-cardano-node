use std::{net::SocketAddr, sync::Arc};

use async_trait::async_trait;
use pingora::{
    apps::ServerApp, connectors::TransportConnector, protocols::Stream, server::ShutdownWatch,
    tls::ssl::NameType, upstreams::peer::BasicPeer,
};
use regex::Regex;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::lookup_host,
    select,
    sync::RwLock,
};
use tracing::error;

use crate::{config::Config, State};

pub struct ProxyApp {
    client_connector: TransportConnector,
    host_regex: Regex,
    state: Arc<RwLock<State>>,
    config: Arc<Config>,
}

enum DuplexEvent {
    DownstreamRead(usize),
    UpstreamRead(usize),
}

impl ProxyApp {
    pub fn new(config: Arc<Config>, state: Arc<RwLock<State>>) -> Self {
        ProxyApp {
            client_connector: TransportConnector::new(None),
            host_regex: Regex::new(r"(dmtr_[\w\d-]+)\.([\w]+)-([\w\d]+).+").unwrap(),
            config,
            state,
        }
    }

    async fn duplex(&self, mut server_session: Stream, mut client_session: Stream) {
        let mut upstream_buf = [0; 1024];
        let mut downstream_buf = [0; 1024];
        loop {
            let downstream_read = server_session.read(&mut upstream_buf);
            let upstream_read = client_session.read(&mut downstream_buf);
            let event: DuplexEvent;
            select! {
                n = downstream_read => event
                    = DuplexEvent::DownstreamRead(n.unwrap()),
                n = upstream_read => event
                    = DuplexEvent::UpstreamRead(n.unwrap()),
            }

            match event {
                DuplexEvent::DownstreamRead(n) => {
                    client_session.write_all(&upstream_buf[0..n]).await.unwrap();
                    client_session.flush().await.unwrap();
                }
                DuplexEvent::UpstreamRead(n) => {
                    server_session
                        .write_all(&downstream_buf[0..n])
                        .await
                        .unwrap();
                    server_session.flush().await.unwrap();
                }
            }
        }
    }
}

#[async_trait]
impl ServerApp for ProxyApp {
    async fn process_new(
        self: &Arc<Self>,
        io: Stream,
        _shutdown: &ShutdownWatch,
    ) -> Option<Stream> {
        let state = self.state.read().await.clone();

        let hostname = io.get_ssl().unwrap().servername(NameType::HOST_NAME);
        if hostname.is_none() {
            error!("hostname is not present in the certificate");
            return None;
        }

        let captures_result = self.host_regex.captures(hostname.unwrap());
        if captures_result.is_none() {
            error!("invalid hostname pattern");
            return None;
        }
        let captures = captures_result.unwrap();

        let token = captures.get(1).unwrap().as_str().to_string();
        let network = captures.get(2).unwrap().as_str().to_string();
        let version = captures.get(3).unwrap().as_str().to_string();

        if !state.is_authenticated(&network, &version, &token) {
            return None;
        }

        let node_host = format!(
            "node-{network}-{version}.{}:{}",
            self.config.node_dns, self.config.node_port
        );

        let lookup_result = lookup_host(node_host).await;
        if let Err(err) = lookup_result {
            error!(error = err.to_string(), "fail to lookup ip");
            return None;
        }
        let lookup: Vec<SocketAddr> = lookup_result.unwrap().collect();
        let node_addr = lookup.first().unwrap();

        let proxy_to = BasicPeer::new(&node_addr.to_string());

        let client_session = self.client_connector.new_stream(&proxy_to).await;

        match client_session {
            Ok(client_session) => {
                self.duplex(io, client_session).await;
                None
            }
            Err(e) => {
                error!("failed to create client session: {}", e);
                None
            }
        }
    }
}
