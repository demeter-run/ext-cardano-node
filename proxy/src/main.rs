use dotenv::dotenv;
use regex::Regex;
use std::{error::Error, sync::Arc};
use tokio::sync::RwLock;
use tracing::Level;

use crate::config::Config;

mod config;
mod proxy;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    dotenv().ok();

    tracing_subscriber::fmt().with_max_level(Level::INFO).init();
    let state = Arc::new(RwLock::new(State::try_new()?));

    let proxy_server = proxy::start(state.clone());

    tokio::join!(proxy_server);

    Ok(())
}

#[derive(Debug, Clone)]
pub struct State {
    config: Config,
    host_regex: Regex,
}
impl State {
    pub fn try_new() -> Result<Self, Box<dyn Error>> {
        let config = Config::new();
        let host_regex = Regex::new(r"(dmtr_[\w\d-]+)\.([\w]+)-([\w\d]+).+")?;

        Ok(Self { config, host_regex })
    }
}
