use std::sync::Arc;

use async_trait::async_trait;
use futures_util::TryStreamExt;
use operator::{
    k8s_openapi::api::core::v1::ConfigMap,
    kube::{
        runtime::watcher::{self},
        Api, Client,
    },
};
use pingora::{server::ShutdownWatch, services::background::BackgroundService};
use serde_json::Value;
use tokio::{pin, sync::RwLock};
use tracing::{error, warn};

use crate::{config::Config, State, Tier};

pub struct TierBackgroundService {
    state: Arc<RwLock<State>>,
    config: Arc<Config>,
}
impl TierBackgroundService {
    pub fn new(state: Arc<RwLock<State>>, config: Arc<Config>) -> Self {
        Self { state, config }
    }
}

#[async_trait]
impl BackgroundService for TierBackgroundService {
    async fn start(&self, mut _shutdown: ShutdownWatch) {
        let client = Client::try_default()
            .await
            .expect("failed to create kube client");

        let api = Api::<ConfigMap>::namespaced(client.clone(), &self.config.proxy_namespace);
        let stream = watcher::watch_object(api, &self.config.proxy_tiers_name);
        pin!(stream);

        loop {
            let stream_result = stream.try_next().await;
            if let Err(err) = stream_result {
                error!(error = err.to_string(), "error to update tier");
                continue;
            }

            if let Some(config_map) = stream_result.unwrap().flatten() {
                if let Some(data) = config_map.data {
                    if let Some(toml_data) = data.get(&self.config.proxy_tiers_key) {
                        let value_result: Result<Value, _> = toml::from_str(toml_data);
                        if let Err(err) = value_result {
                            error!(error = err.to_string(), "error to deserialize toml");
                            continue;
                        }

                        let tiers_value: Option<&Value> =
                            value_result.as_ref().unwrap().get("tiers");
                        if tiers_value.is_none() {
                            warn!("tiers not configured on toml");
                            continue;
                        }

                        let tiers =
                            serde_json::from_value::<Vec<Tier>>(tiers_value.unwrap().to_owned())
                                .unwrap();

                        self.state.write().await.tiers = tiers
                            .into_iter()
                            .map(|tier| (tier.name.clone(), tier))
                            .collect();
                    }
                }
            }
        }
    }
}
