use std::{env, path::PathBuf, time::Duration};

#[derive(Debug, Clone)]
pub struct Config {
    pub proxy_addr: String,
    pub proxy_namespace: String,
    pub proxy_tiers_path: PathBuf,
    pub proxy_tiers_poll_interval: Duration,
    pub prometheus_addr: String,
    pub ssl_crt_path: String,
    pub ssl_key_path: String,
    pub node_port: u16,
    pub node_dns: String,
}
impl Config {
    pub fn new() -> Self {
        Self {
            proxy_addr: env::var("PROXY_ADDR").expect("PROXY_ADDR must be set"),
            proxy_namespace: env::var("PROXY_NAMESPACE").expect("PROXY_NAMESPACE must be set"),
            proxy_tiers_path: env::var("PROXY_TIERS_PATH")
                .map(|v| v.into())
                .expect("PROXY_TIERS_PATH must be set"),
            proxy_tiers_poll_interval: env::var("PROXY_TIERS_POLL_INTERVAL")
                .map(|v| {
                    Duration::from_secs(
                        v.parse::<u64>()
                            .expect("PROXY_TIERS_POLL_INTERVAL must be a number in seconds. eg: 2"),
                    )
                })
                .unwrap_or(Duration::from_secs(2)),
            prometheus_addr: env::var("PROMETHEUS_ADDR").expect("PROMETHEUS_ADDR must be set"),
            ssl_crt_path: env::var("SSL_CRT_PATH").expect("SSL_CRT_PATH must be set"),
            ssl_key_path: env::var("SSL_KEY_PATH").expect("SSL_KEY_PATH must be set"),
            node_port: env::var("NODE_PORT")
                .expect("NODE_PORT must be set")
                .parse()
                .expect("NODE_PORT must a number"),
            node_dns: env::var("NODE_DNS").expect("NODE_DNS must be set"),
        }
    }
}
impl Default for Config {
    fn default() -> Self {
        Self::new()
    }
}
