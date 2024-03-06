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
}

#[async_trait]
impl ServerApp for ProxyApp {
    async fn process_new(
        self: &Arc<Self>,
        mut io_server: Stream,
        _shutdown: &ShutdownWatch,
    ) -> Option<Stream> {
        let state = self.state.read().await.clone();

        let hostname = io_server.get_ssl()?.servername(NameType::HOST_NAME);
        if hostname.is_none() {
            error!("hostname is not present in the certificate");
            return None;
        }

        let captures_result = self.host_regex.captures(hostname?);
        if captures_result.is_none() {
            error!("invalid hostname pattern");
            return None;
        }
        let captures = captures_result?;

        let token = captures.get(1)?.as_str().to_string();
        let network = captures.get(2)?.as_str().to_string();
        let version = captures.get(3)?.as_str().to_string();
        let namespace = self.config.proxy_namespace.clone();
        
        let consumer = state.get_consumer(&network, &version, &token)?;

        let instance = format!(
            "node-{network}-{version}.{}:{}",
            self.config.node_dns, self.config.node_port
        );

        let lookup_result = lookup_host(&instance).await;
        if let Err(err) = lookup_result {
            error!(error = err.to_string(), "fail to lookup ip");
            return None;
        }
        let lookup: Vec<SocketAddr> = lookup_result.unwrap().collect();
        let node_addr = lookup.first()?;

        let proxy_to = BasicPeer::new(&node_addr.to_string());

        let io_client = self.client_connector.new_stream(&proxy_to).await;

        match io_client {
            Ok(mut io_client) => {
                let mut upstream_buf = [0; 1024];
                let mut downstream_buf = [0; 1024];

                loop {
                    let downstream_read = io_server.read(&mut upstream_buf);
                    let upstream_read = io_client.read(&mut downstream_buf);
                    let event: DuplexEvent;

                    select! {
                        n = downstream_read => {
                            if let Err(err) = &n {
                                error!(error=err.to_string(), "Downstream error");
                                return None;
                            }
                            event = DuplexEvent::DownstreamRead(n.unwrap())
                        },
                        n = upstream_read => {
                            if let Err(err) = &n {
                                error!(error=err.to_string(), "Upstream error");
                                return None;
                            }
                            event = DuplexEvent::UpstreamRead(n.unwrap())
                        },
                    }

                    match event {
                        DuplexEvent::DownstreamRead(0) => {
                            return None;
                        }
                        DuplexEvent::UpstreamRead(0) => {
                            return None;
                        }
                        DuplexEvent::DownstreamRead(n) => {
                            state
                                .metrics
                                .count_total_packages_bytes(&consumer, &namespace, &instance, n);

                            io_client.write_all(&upstream_buf[0..n]).await.unwrap();
                            io_client.flush().await.unwrap();
                        }
                        DuplexEvent::UpstreamRead(n) => {
                            state
                                .metrics
                                .count_total_packages_bytes(&consumer, &namespace, &instance, n);

                            io_server.write_all(&downstream_buf[0..n]).await.unwrap();
                            io_server.flush().await.unwrap();
                        }
                    }
                }
            }
            Err(e) => {
                error!("failed to create client session: {}", e);
                None
            }
        }
    }
}
