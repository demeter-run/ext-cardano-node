use std::{collections::HashMap, fmt::Display, sync::Arc};

use auth::AuthBackgroundService;
use dotenv::dotenv;
use leaky_bucket::RateLimiter;
use pingora::{
    listeners::Listeners,
    server::{configuration::Opt, Server},
    services::{background::background_service, listening::Service},
};
use prometheus::{opts, register_int_counter_vec, register_int_gauge_vec};
use proxy::ProxyApp;
use serde::Deserialize;
use tiers::TierBackgroundService;
use tokio::sync::{Mutex, RwLock};
use tracing::Level;

use crate::config::Config;

mod auth;
mod config;
mod proxy;
mod tiers;

fn main() {
    dotenv().ok();

    tracing_subscriber::fmt().with_max_level(Level::INFO).init();

    let config: Arc<Config> = Arc::default();
    let state: Arc<RwLock<State>> = Arc::default();

    let opt = Opt::default();
    let mut server = Server::new(Some(opt)).unwrap();
    server.bootstrap();

    let auth_background_service = background_service(
        "K8S Auth Service",
        AuthBackgroundService::new(state.clone()),
    );
    server.add_service(auth_background_service);

    let tier_background_service = background_service(
        "K8S Tier Service",
        TierBackgroundService::new(state.clone(), config.clone()),
    );
    server.add_service(tier_background_service);

    let tls_proxy_service = Service::with_listeners(
        "TLS Proxy Service".to_string(),
        Listeners::tls(
            &config.proxy_addr,
            &config.ssl_crt_path,
            &config.ssl_key_path,
        )
        .unwrap(),
        Arc::new(ProxyApp::new(config.clone(), state)),
    );
    server.add_service(tls_proxy_service);

    let mut prometheus_service_http =
        pingora::services::listening::Service::prometheus_http_service();
    prometheus_service_http.add_tcp(&config.prometheus_addr);
    server.add_service(prometheus_service_http);

    server.run_forever();
}

#[derive(Clone, Default)]
pub struct State {
    metrics: Metrics,
    consumers: HashMap<String, Consumer>,
    limiter: Arc<Mutex<HashMap<String, RateLimiter>>>,
    tiers: HashMap<String, Tier>,
}
impl State {
    pub fn new() -> Self {
        let metrics = Metrics::new();
        let consumers = HashMap::new();
        let limiter = Default::default();
        let tiers = HashMap::new();

        Self {
            metrics,
            consumers,
            limiter,
            tiers,
        }
    }

    pub fn get_consumer(&self, network: &str, version: &str, token: &str) -> Option<Consumer> {
        let hash_key = format!("{}.{}.{}", network, version, token);
        self.consumers.get(&hash_key).cloned()
    }
}

#[derive(Debug, Clone, Default)]
pub struct Consumer {
    namespace: String,
    port_name: String,
    token: String,
}
impl Consumer {
    pub fn new(namespace: String, port_name: String, token: String) -> Self {
        Self {
            namespace,
            port_name,
            token,
        }
    }
}
impl Display for Consumer {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}.{}", self.namespace, self.port_name)
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct Tier {
    name: String,
    max_connections: u32,
    max_bytes_per_minute: u32,
}

#[derive(Debug, Clone)]
pub struct Metrics {
    total_packages_bytes: prometheus::IntCounterVec,
    total_connections: prometheus::IntGaugeVec,
}
impl Metrics {
    pub fn new() -> Self {
        let total_connections = register_int_gauge_vec!(
            opts!("node_proxy_total_connections", "Total connections",),
            &["consumer", "namespace", "instance"]
        )
        .unwrap();

        let total_packages_bytes = register_int_counter_vec!(
            opts!("node_proxy_total_packages_bytes", "Total bytes transferred",),
            &["consumer", "namespace", "instance"]
        )
        .unwrap();

        Self {
            total_packages_bytes,
            total_connections,
        }
    }

    pub fn count_total_packages_bytes(
        &self,
        consumer: &Consumer,
        namespace: &str,
        instance: &str,
        value: usize,
    ) {
        let consumer = &consumer.to_string();

        self.total_packages_bytes
            .with_label_values(&[consumer, namespace, instance])
            .inc_by(value as u64)
    }

    pub fn inc_total_connections(&self, consumer: &Consumer, namespace: &str, instance: &str) {
        let consumer = &consumer.to_string();

        self.total_connections
            .with_label_values(&[consumer, namespace, instance])
            .inc()
    }

    pub fn dec_total_connections(&self, consumer: &Consumer, namespace: &str, instance: &str) {
        let consumer = &consumer.to_string();

        self.total_connections
            .with_label_values(&[consumer, namespace, instance])
            .dec()
    }
}
impl Default for Metrics {
    fn default() -> Self {
        Self::new()
    }
}
