use std::{collections::HashMap, sync::Arc};

use async_trait::async_trait;
use futures_util::TryStreamExt;
use operator::{
    kube::{
        runtime::watcher::{self, Config, Event},
        Api, Client, ResourceExt,
    },
    CardanoNodePort,
};
use pingora::{server::ShutdownWatch, services::background::BackgroundService};
use tokio::pin;
use tracing::{error, info};

use crate::{Consumer, State};

pub struct AuthBackgroundService {
    state: Arc<State>,
}
impl AuthBackgroundService {
    pub fn new(state: Arc<State>) -> Self {
        Self { state }
    }

    async fn sync_consumer(&self, mut consumer: Consumer) -> Consumer {
        if let Some(old_consumer) = self.state.consumers.read().await.clone().get(&consumer.key) {
            consumer.active_connections = old_consumer.active_connections;
        }
        consumer
    }
}

#[async_trait]
impl BackgroundService for AuthBackgroundService {
    async fn start(&self, mut _shutdown: ShutdownWatch) {
        let client = Client::try_default()
            .await
            .expect("failed to create kube client");

        let api = Api::<CardanoNodePort>::all(client.clone());
        let stream = watcher::watcher(api.clone(), Config::default());

        pin!(stream);

        loop {
            let result = stream.try_next().await;
            match result {
                // Stream restart, also run on startup.
                Ok(Some(Event::Restarted(crds))) => {
                    info!("auth: Watcher restarted, reseting consumers");

                    let mut consumers: HashMap<String, Consumer> = Default::default();
                    for crd in crds.iter() {
                        let consumer = self.sync_consumer(crd.into()).await;
                        consumers.insert(consumer.key.clone(), consumer);
                    }

                    *self.state.consumers.write().await = consumers;
                    self.state.limiter.write().await.clear();
                }
                // New port created or updated.
                Ok(Some(Event::Applied(crd))) => match crd.status {
                    Some(_) => {
                        info!("auth: Adding new consumer: {}", crd.name_any());

                        let consumer = self.sync_consumer((&crd).into()).await;

                        self.state.limiter.write().await.remove(&consumer.key);
                        self.state
                            .consumers
                            .write()
                            .await
                            .insert(consumer.key.clone(), consumer);
                    }
                    None => {
                        // New ports are created without status. When the status is added, a new
                        // Applied event is triggered.
                        info!("auth: New port created: {}", crd.name_any());
                    }
                },
                // Port deleted.
                Ok(Some(Event::Deleted(crd))) => {
                    info!(
                        "auth: Port deleted, removing from state: {}",
                        crd.name_any()
                    );
                    let consumer = Consumer::from(&crd);
                    self.state.consumers.write().await.remove(&consumer.key);
                    self.state.limiter.write().await.remove(&consumer.key);
                }
                // Empty response from stream. Should never happen.
                Ok(None) => {
                    error!("auth: Empty response from watcher.");
                    continue;
                }
                // Unexpected error when streaming CRDs.
                Err(err) => {
                    error!(error = err.to_string(), "auth: Failed to update crds.");
                    std::process::exit(1);
                }
            }
        }
    }
}
