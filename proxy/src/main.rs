use std::{collections::HashMap, fmt::Display, sync::Arc, time::Duration};

use auth::AuthBackgroundService;
use dotenv::dotenv;
use leaky_bucket::RateLimiter;
use operator::{kube::ResourceExt, CardanoNodePort};
use pingora::{
    listeners::Listeners,
    server::{configuration::Opt, Server},
    services::{background::background_service, listening::Service},
};
use prometheus::{opts, register_int_counter_vec, register_int_gauge_vec};
use proxy::ProxyApp;
use regex::Regex;
use serde::{Deserialize, Deserializer};
use tiers::TierBackgroundService;
use tokio::sync::RwLock;
use tracing_subscriber::{fmt, layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

use crate::config::Config;

mod auth;
mod config;
mod proxy;
mod tiers;

fn main() {
    dotenv().ok();

    tracing_subscriber::registry()
        .with(fmt::layer())
        .with(EnvFilter::from_default_env())
        .init();

    let config: Arc<Config> = Arc::default();
    let state: Arc<State> = Arc::default();

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

#[derive(Default)]
pub struct State {
    metrics: Metrics,
    consumers: RwLock<HashMap<String, Consumer>>,
    limiter: RwLock<HashMap<String, Vec<Arc<RateLimiter>>>>,
    tiers: RwLock<HashMap<String, Tier>>,
}
impl State {
    pub fn new() -> Self {
        Self::default()
    }

    pub async fn get_consumer(&self, key: &str) -> Option<Consumer> {
        let consumers = self.consumers.read().await.clone();
        consumers.get(key).cloned()
    }
}

#[derive(Debug, Clone, Default)]
pub struct Consumer {
    namespace: String,
    port_name: String,
    tier: String,
    key: String,
    network: String,
    version: String,
    active_connections: usize,
}
impl Consumer {
    pub async fn inc_connections(&mut self, state: Arc<State>) {
        self.active_connections += 1;
        state
            .consumers
            .write()
            .await
            .insert(self.key.clone(), self.clone());
    }
    pub async fn dec_connections(&mut self, state: Arc<State>) {
        self.active_connections -= 1;
        state
            .consumers
            .write()
            .await
            .insert(self.key.clone(), self.clone());
    }
}
impl Display for Consumer {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}.{}", self.namespace, self.port_name)
    }
}
impl From<&CardanoNodePort> for Consumer {
    fn from(value: &CardanoNodePort) -> Self {
        let network = value.spec.network.to_string();
        let version = value.spec.version.to_string();
        let tier = value.spec.throughput_tier.to_string();
        let key = value.status.as_ref().unwrap().auth_token.clone();
        let namespace = value.metadata.namespace.as_ref().unwrap().clone();
        let port_name = value.name_any();

        Self {
            namespace,
            port_name,
            tier,
            key,
            network,
            version,
            active_connections: 0,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct Tier {
    name: String,
    rates: Vec<TierRate>,
    max_connections: usize,
}
#[derive(Debug, Clone, Deserialize)]
pub struct TierRate {
    limit: usize,
    #[serde(deserialize_with = "deserialize_duration")]
    interval: Duration,
}
pub fn deserialize_duration<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> Result<Duration, D::Error> {
    let value: String = Deserialize::deserialize(deserializer)?;
    let regex = Regex::new(r"([\d]+)([\w])").unwrap();
    let captures = regex.captures(&value);
    if captures.is_none() {
        return Err(<D::Error as serde::de::Error>::custom(
            "Invalid tier interval format",
        ));
    }

    let captures = captures.unwrap();
    let number = captures.get(1).unwrap().as_str().parse::<u64>().unwrap();
    let symbol = captures.get(2).unwrap().as_str();

    match symbol {
        "s" => Ok(Duration::from_secs(number)),
        "m" => Ok(Duration::from_secs(number * 60)),
        "h" => Ok(Duration::from_secs(number * 60 * 60)),
        "d" => Ok(Duration::from_secs(number * 60 * 60 * 24)),
        _ => Err(<D::Error as serde::de::Error>::custom(
            "Invalid symbol tier interval",
        )),
    }
}

#[derive(Debug, Clone)]
pub struct Metrics {
    total_packages_bytes: prometheus::IntCounterVec,
    total_connections: prometheus::IntGaugeVec,
    total_connections_denied: prometheus::IntCounterVec,
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

        let total_connections_denied = register_int_counter_vec!(
            opts!(
                "node_proxy_total_connections_denied",
                "Total denied connections",
            ),
            &["consumer", "namespace", "instance"]
        )
        .unwrap();

        Self {
            total_packages_bytes,
            total_connections,
            total_connections_denied,
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

    pub fn count_total_connections_denied(
        &self,
        consumer: &Consumer,
        namespace: &str,
        instance: &str,
    ) {
        let consumer = &consumer.to_string();

        self.total_connections_denied
            .with_label_values(&[consumer, namespace, instance])
            .inc()
    }
}
impl Default for Metrics {
    fn default() -> Self {
        Self::new()
    }
}
