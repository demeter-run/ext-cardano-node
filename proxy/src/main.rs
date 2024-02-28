use dotenv::dotenv;
use metrics::Metrics;
use prometheus::Registry;
use regex::Regex;
use std::{collections::HashMap, error::Error, fmt::Display, sync::Arc};
use tokio::sync::RwLock;
use tracing::Level;

use crate::config::Config;

mod auth;
mod config;
mod metrics;
mod proxy;
mod utils;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    dotenv().ok();

    tracing_subscriber::fmt().with_max_level(Level::INFO).init();
    let state = Arc::new(RwLock::new(State::try_new()?));

    let auth = auth::start(state.clone());
    let metrics = metrics::start(state.clone());
    let proxy_server = proxy::start(state.clone());

    tokio::join!(auth, metrics, proxy_server);

    Ok(())
}

#[derive(Debug, Clone)]
pub struct State {
    config: Config,
    metrics: Metrics,
    host_regex: Regex,
    consumers: HashMap<String, Consumer>,
}
impl State {
    pub fn try_new() -> Result<Self, Box<dyn Error>> {
        let config = Config::new();
        let metrics = Metrics::try_new(Registry::default())?;
        let host_regex = Regex::new(r"(dmtr_[\w\d-]+)\.([\w]+)-([\w\d]+).+")?;
        let consumers = HashMap::new();

        Ok(Self {
            config,
            metrics,
            host_regex,
            consumers,
        })
    }

    pub fn is_authenticated(&self, network: &str, version: &str, token: &str) -> bool {
        let hash_key = format!("{}.{}.{}", network, version, token);
        self.consumers.get(&hash_key).is_some()
    }
}

#[derive(Debug, Clone, Default)]
pub struct Consumer {
    namespace: String,
    port_name: String,
}
impl Consumer {
    pub fn new(namespace: String, port_name: String) -> Self {
        Self {
            namespace,
            port_name,
        }
    }
}
impl Display for Consumer {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}.{}", self.namespace, self.port_name)
    }
}
