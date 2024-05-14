use lazy_static::lazy_static;
use std::{collections::HashMap, env, time::Duration};

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
    pub api_key_salt: String,
    pub metrics_delay: Duration,
    pub prometheus_url: String,
    pub dcu_per_second: HashMap<String, f64>,
}

impl Config {
    pub fn from_env() -> Self {
        Self {
            dns_zone: env::var("DNS_ZONE").unwrap_or("demeter.run".into()),
            extension_name: env::var("EXTENSION_NAME").unwrap_or("node-m1".into()),
            api_key_salt: env::var("API_KEY_SALT").unwrap_or("cardano-node-salt".into()),
            metrics_delay: Duration::from_secs(
                std::env::var("METRICS_DELAY")
                    .expect("METRICS_DELAY must be set")
                    .parse::<u64>()
                    .expect("METRICS_DELAY must be a number"),
            ),
            prometheus_url: env::var("PROMETHEUS_URL").expect("PROMETHEUS_URL must be set"),
            dcu_per_second: env::var("DCU_PER_SECOND")
                .expect("DCU_PER_SECOND must be set")
                .split(',')
                .map(|pair| {
                    let parts: Vec<&str> = pair.split('=').collect();
                    let dcu = parts[1]
                        .parse::<f64>()
                        .expect("DCU_PER_SECOND must be NETWORK=NUMBER");

                    (parts[0].into(), dcu)
                })
                .collect(),
        }
    }
}
