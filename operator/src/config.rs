use lazy_static::lazy_static;
use std::env;

lazy_static! {
    static ref CONTROLLER_CONFIG: Config = Config::from_env();
}

pub fn get_config() -> &'static Config {
    &CONTROLLER_CONFIG
}

#[derive(Debug, Clone)]
pub struct Config {
    pub dns_zone: String,
    pub extension_name: String,
    pub node_port: u16,
    pub api_key_salt: String,
}

impl Config {
    pub fn from_env() -> Self {
        Self {
            dns_zone: env::var("DNS_ZONE").unwrap_or("demeter.run".into()),
            extension_name: env::var("EXTENSION_NAME").unwrap_or("node-m1".into()),
            node_port: env::var("NODE_PORT")
                .map(|e| e.parse().expect("NODE_PORT must be a number u16"))
                .unwrap_or(9443),
            api_key_salt: env::var("API_KEY_SALT").unwrap_or("cardano-node-salt".into()),
        }
    }
}
