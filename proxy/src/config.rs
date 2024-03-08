use std::env;

#[derive(Debug, Clone)]
pub struct Config {
    pub proxy_addr: String,
    pub proxy_namespace: String,
    pub proxy_tiers_name: String,
    pub proxy_tiers_key: String,
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
            proxy_tiers_name: env::var("PROXY_TIERS_NAME").expect("PROXY_TIERS_NAME must be set"),
            proxy_tiers_key: env::var("PROXY_TIERS_KEY").expect("PROXY_TIERS_KEY must be set"),
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
