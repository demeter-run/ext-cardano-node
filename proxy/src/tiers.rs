use async_trait::async_trait;
use notify::{PollWatcher, RecursiveMode, Watcher};
use pingora::{server::ShutdownWatch, services::background::BackgroundService};
use serde_json::Value;
use std::error::Error;
use std::{fs, sync::Arc};
use tracing::{error, info, warn};

use crate::{config::Config, State, Tier};

pub struct TierBackgroundService {
    state: Arc<State>,
    config: Arc<Config>,
}
impl TierBackgroundService {
    pub fn new(state: Arc<State>, config: Arc<Config>) -> Self {
        Self { state, config }
    }

    async fn update_tiers(&self) -> Result<(), Box<dyn Error>> {
        let contents = fs::read_to_string(&self.config.proxy_tiers_path)?;

        let value: Value = toml::from_str(&contents)?;
        let tiers_value: Option<&Value> = value.get("tiers");
        if tiers_value.is_none() {
            warn!("tiers not configured on toml");
            return Ok(());
        }

        let tiers = serde_json::from_value::<Vec<Tier>>(tiers_value.unwrap().to_owned())?;

        *self.state.tiers.write().await = tiers
            .into_iter()
            .map(|tier| (tier.name.clone(), tier))
            .collect();

        self.state.limiter.write().await.clear();

        Ok(())
    }
}

#[async_trait]
impl BackgroundService for TierBackgroundService {
    async fn start(&self, mut _shutdown: ShutdownWatch) {
        if let Err(err) = self.update_tiers().await {
            error!(error = err.to_string(), "error to update tiers");
            return;
        }

        let (tx, rx) = std::sync::mpsc::channel();

        let watcher_config = notify::Config::default()
            .with_compare_contents(true)
            .with_poll_interval(self.config.proxy_tiers_poll_interval);

        let watcher_result = PollWatcher::new(tx, watcher_config);
        if let Err(err) = watcher_result {
            error!(error = err.to_string(), "error to watcher tier");
            return;
        }

        let mut watcher = watcher_result.unwrap();
        let watcher_result = watcher.watch(&self.config.proxy_tiers_path, RecursiveMode::Recursive);
        if let Err(err) = watcher_result {
            error!(error = err.to_string(), "error to watcher tier");
            return;
        }

        for result in rx {
            match result {
                Ok(_event) => {
                    if let Err(err) = self.update_tiers().await {
                        error!(error = err.to_string(), "error to update tiers");
                        continue;
                    }

                    info!("tiers modified");
                }
                Err(err) => error!(error = err.to_string(), "watch error"),
            }
        }
    }
}
