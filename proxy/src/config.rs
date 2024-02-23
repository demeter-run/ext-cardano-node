use std::{env, path::PathBuf};

#[derive(Debug, Clone)]
pub struct Config {
    pub proxy_addr: String,
    pub node_addr: String,
    pub ssl_crt_path: PathBuf,
    pub ssl_key_path: PathBuf,
}

impl Config {
    pub fn new() -> Self {
        Self {
            proxy_addr: env::var("PROXY_ADDR").expect("PROXY_ADDR must be set"),
            node_addr: env::var("NODE_ADDR").expect("NODE_ADDR must be set"),
            ssl_crt_path: env::var("SSL_CRT_PATH")
                .map(|e| e.into())
                .expect("SSL_CRT_PATH must be set"),
            ssl_key_path: env::var("SSL_KEY_PATH")
                .map(|e| e.into())
                .expect("SSL_KEY_PATH must be set"),
        }
    }
}
