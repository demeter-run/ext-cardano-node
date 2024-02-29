use std::env;

#[derive(Debug, Clone)]
pub struct Config {
    pub proxy_addr: String,
    pub ssl_crt_path: String,
    pub ssl_key_path: String,
    pub node_port: u16,
    pub node_dns: String,
}

impl Config {
    pub fn new() -> Self {
        Self {
            proxy_addr: env::var("PROXY_ADDR").expect("PROXY_ADDR must be set"),
            ssl_crt_path: env::var("SSL_CRT_PATH")
                .map(|e| e.into())
                .expect("SSL_CRT_PATH must be set"),
            ssl_key_path: env::var("SSL_KEY_PATH")
                .map(|e| e.into())
                .expect("SSL_KEY_PATH must be set"),
            node_port: env::var("NODE_PORT")
                .expect("NODE_PORT must be set")
                .parse()
                .expect("NODE_PORT must a number"),
            node_dns: env::var("NODE_DNS").expect("NODE_DNS must be set"),
        }
    }
}
