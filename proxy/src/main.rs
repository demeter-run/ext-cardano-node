use std::{collections::HashMap, fmt::Display, sync::Arc};

use auth::AuthBackgroundService;
use dotenv::dotenv;
use pingora::{
    listeners::Listeners,
    server::{configuration::Opt, Server},
    services::{background::background_service, listening::Service},
};
use proxy::ProxyApp;
use tokio::sync::RwLock;
use tracing::Level;

use crate::config::Config;

mod auth;
mod config;
mod proxy;

fn main() {
    dotenv().ok();

    tracing_subscriber::fmt().with_max_level(Level::INFO).init();

    let config = Arc::new(Config::new());
    let state = Arc::new(RwLock::new(State::new()));

    let opt = Opt::default();
    let mut server = Server::new(Some(opt)).unwrap();
    server.bootstrap();

    let auth_background_service = background_service(
        "K8S Auth Service",
        AuthBackgroundService::new(state.clone()),
    );
    server.add_service(auth_background_service);

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
    prometheus_service_http.add_tcp(&config.proxy_addr);
    server.add_service(prometheus_service_http);

    server.run_forever();
}

#[derive(Debug, Clone)]
pub struct State {
    consumers: HashMap<String, Consumer>,
}
impl State {
    pub fn new() -> Self {
        let consumers = HashMap::new();
        Self { consumers }
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
