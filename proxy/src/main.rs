use std::{collections::HashMap, error::Error, fmt::Display, sync::Arc, time::Duration};

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
use tracing::Level;
use tracing_subscriber::{fmt, layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

use crate::config::Config;

mod auth;
mod config;
mod proxy;
mod tiers;

fn main() {
    dotenv().ok();

    let env_filter = EnvFilter::builder()
        .with_default_directive(Level::INFO.into())
        .with_env_var("RUST_LOG")
        .from_env_lossy();

    tracing_subscriber::registry()
        .with(fmt::layer())
        .with(env_filter)
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
    consumers: RwLock<HashMap<Vec<u8>, Consumer>>,
    limiter: RwLock<HashMap<Vec<u8>, Vec<Arc<RateLimiter>>>>,
    tiers: RwLock<HashMap<String, Tier>>,
}
impl State {
    pub fn new() -> Self {
        Self::default()
    }

    pub async fn get_consumer(&self, key: &[u8]) -> Option<Consumer> {
        let consumers = self.consumers.read().await.clone();
        consumers.get(key).cloned()
    }
}

#[derive(Debug, Clone, Default)]
pub struct Consumer {
    namespace: String,
    port_name: String,
    tier: String,
    key: Vec<u8>,
    network: String,
    version: String,
    active_connections: usize,
}
impl Consumer {
    pub fn new(crd: &CardanoNodePort) -> Result<Self, Box<dyn Error>> {
        let network = crd.spec.network.to_string();
        let version = crd.spec.version.to_string();
        let tier = crd.spec.throughput_tier.to_string();
        let key = crd.status.as_ref().unwrap().auth_token.clone();
        let namespace = crd.metadata.namespace.as_ref().unwrap().clone();
        let port_name = crd.name_any();

        let (_hrp, key) = bech32::decode(&key)?;

        Ok(Self {
            namespace,
            port_name,
            tier,
            key,
            network,
            version,
            active_connections: 0,
        })
    }
    pub async fn inc_connections(&self, state: Arc<State>) {
        state
            .consumers
            .write()
            .await
            .entry(self.key.clone())
            .and_modify(|consumer| consumer.active_connections += 1);
    }
    pub async fn dec_connections(&mut self, state: Arc<State>) {
        state
            .consumers
            .write()
            .await
            .entry(self.key.clone())
            .and_modify(|consumer| consumer.active_connections -= 1);
    }
    pub async fn get_active_connections(&self, state: Arc<State>) -> usize {
        state
            .consumers
            .read()
            .await
            .get(&self.key)
            .map(|consumer| consumer.active_connections)
            .unwrap_or_default()
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
            &["consumer", "namespace", "instance", "tier"]
        )
        .unwrap();

        let total_packages_bytes = register_int_counter_vec!(
            opts!("node_proxy_total_packages_bytes", "Total bytes transferred",),
            &["consumer", "namespace", "instance", "tier"]
        )
        .unwrap();

        let total_connections_denied = register_int_counter_vec!(
            opts!(
                "node_proxy_total_connections_denied",
                "Total denied connections",
            ),
            &["consumer", "namespace", "instance", "tier"]
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
        self.total_packages_bytes
            .with_label_values(&[&consumer.to_string(), namespace, instance, &consumer.tier])
            .inc_by(value as u64)
    }

    pub fn inc_total_connections(&self, consumer: &Consumer, namespace: &str, instance: &str) {
        self.total_connections
            .with_label_values(&[&consumer.to_string(), namespace, instance, &consumer.tier])
            .inc()
    }

    pub fn dec_total_connections(&self, consumer: &Consumer, namespace: &str, instance: &str) {
        self.total_connections
            .with_label_values(&[&consumer.to_string(), namespace, instance, &consumer.tier])
            .dec()
    }

    pub fn count_total_connections_denied(
        &self,
        consumer: &Consumer,
        namespace: &str,
        instance: &str,
    ) {
        self.total_connections_denied
            .with_label_values(&[&consumer.to_string(), namespace, instance, &consumer.tier])
            .inc()
    }
}
impl Default for Metrics {
    fn default() -> Self {
        Self::new()
    }
}
