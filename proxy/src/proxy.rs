use async_trait::async_trait;
use lazy_static::lazy_static;
use pingora::{
    apps::ServerApp, connectors::TransportConnector, protocols::Stream, server::ShutdownWatch,
    tls::ssl::NameType, upstreams::peer::BasicPeer,
};
use pingora_limits::rate::Rate;
use regex::Regex;
use std::{
    collections::HashMap,
    net::SocketAddr,
    sync::{Arc, Mutex},
    time::Duration,
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::lookup_host,
    select,
    sync::RwLock,
    time::sleep,
};
use tracing::error;

use crate::{config::Config, Consumer, State};

lazy_static! {
    static ref RATE_LIMITER_MAP: Arc<Mutex<HashMap<String, Rate>>> =
        Arc::new(Mutex::new(HashMap::new()));
}
const RATE_DURATION: Duration = Duration::from_secs(1);

enum DuplexEvent {
    ClientRead(usize),
    InstanceRead(usize),
}

struct MetricData {
    consumer: Consumer,
    namespace: String,
    instance: String,
}
impl MetricData {
    pub fn new(consumer: &Consumer, instance: &str, namespace: &str) -> Self {
        Self {
            consumer: consumer.clone(),
            namespace: namespace.into(),
            instance: instance.into(),
        }
    }
}

pub struct ProxyApp {
    client_connector: TransportConnector,
    host_regex: Regex,
    state: Arc<RwLock<State>>,
    config: Arc<Config>,
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

    async fn duplex(
        &self,
        mut io_client: Stream,
        mut io_instance: Stream,
        state: State,
        metric_data: MetricData,
    ) {
        state.metrics.inc_total_connections(
            &metric_data.consumer,
            &metric_data.namespace,
            &metric_data.instance,
        );

        let mut io_client_buf = [0; 1024];
        let mut io_instance_buf = [0; 1024];

        loop {
            let event: DuplexEvent;

            select! {
                n = io_client.read(&mut io_client_buf) => event = DuplexEvent::ClientRead(n.unwrap()),
                n = io_instance.read(&mut io_instance_buf) => event = DuplexEvent::InstanceRead(n.unwrap()),
            }

            match event {
                DuplexEvent::ClientRead(0) | DuplexEvent::InstanceRead(0) => {
                    state.metrics.dec_total_connections(
                        &metric_data.consumer,
                        &metric_data.namespace,
                        &metric_data.instance,
                    );

                    return;
                }

                DuplexEvent::ClientRead(bytes) => {
                    if limiter(&metric_data.consumer.token) >= 10 {
                        sleep(RATE_DURATION).await;
                    }

                    state.metrics.count_total_packages_bytes(
                        &metric_data.consumer,
                        &metric_data.namespace,
                        &metric_data.instance,
                        bytes,
                    );

                    // TODO: validate results
                    let _ = io_instance.write_all(&io_client_buf[0..bytes]).await;
                    let _ = io_instance.flush().await;
                }
                DuplexEvent::InstanceRead(bytes) => {
                    state.metrics.count_total_packages_bytes(
                        &metric_data.consumer,
                        &metric_data.namespace,
                        &metric_data.instance,
                        bytes,
                    );

                    // TODO: validate results
                    let _ = io_client.write_all(&io_instance_buf[0..bytes]).await;
                    let _ = io_client.flush().await;
                }
            }
        }
    }
}

#[async_trait]
impl ServerApp for ProxyApp {
    async fn process_new(
        self: &Arc<Self>,
        io_client: Stream,
        _shutdown: &ShutdownWatch,
    ) -> Option<Stream> {
        let state = self.state.read().await.clone();

        let hostname = io_client.get_ssl()?.servername(NameType::HOST_NAME);
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

        let metric_data = MetricData::new(&consumer, &instance, &namespace);

        let lookup_result = lookup_host(&instance).await;
        if let Err(err) = lookup_result {
            error!(error = err.to_string(), "fail to lookup ip");
            return None;
        }
        let lookup: Vec<SocketAddr> = lookup_result.unwrap().collect();
        let node_addr = lookup.first()?;

        let proxy_to = BasicPeer::new(&node_addr.to_string());

        let io_instance = self.client_connector.new_stream(&proxy_to).await;

        match io_instance {
            Ok(io_instance) => {
                self.duplex(io_client, io_instance, state, metric_data)
                    .await;
                None
            }
            Err(e) => {
                error!("failed to create instance session: {}", e);
                None
            }
        }
    }
}

fn limiter(key: &String) -> isize {
    let mut rate_limiter_map = RATE_LIMITER_MAP.lock().unwrap();
    let rate_limiter = match rate_limiter_map.get(key) {
        None => {
            let limiter = Rate::new(RATE_DURATION);
            rate_limiter_map.insert(key.into(), limiter);
            rate_limiter_map.get(key).unwrap()
        }
        Some(limiter) => limiter,
    };

    rate_limiter.observe(key, 1)
}
