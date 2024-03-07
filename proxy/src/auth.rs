use std::{collections::HashMap, sync::Arc};

use async_trait::async_trait;
use futures_util::TryStreamExt;
use operator::{
    kube::{
        api::ListParams,
        runtime::{
            watcher::{self, Config},
            WatchStreamExt,
        },
        Api, Client, ResourceExt,
    },
    CardanoNodePort,
};
use pingora::{server::ShutdownWatch, services::background::BackgroundService};
use tokio::{pin, sync::RwLock};
use tracing::error;

use crate::{Consumer, State};

#[derive(Debug)]
pub struct AuthBackgroundService {
    state: Arc<RwLock<State>>,
}
impl AuthBackgroundService {
    pub fn new(state: Arc<RwLock<State>>) -> Self {
        Self { state }
    }

    async fn update_auth(&self, api: Api<CardanoNodePort>) {
        let result = api.list(&ListParams::default()).await;
        if let Err(err) = result {
            error!(
                error = err.to_string(),
                "error to get crds while updating auth keys"
            );
            return;
        }

        let mut consumers = HashMap::new();
        for crd in result.unwrap().items.iter() {
            if crd.status.is_some() {
                let network = crd.spec.network.to_string();
                let version = crd.spec.version.clone();
                let token = crd.status.as_ref().unwrap().auth_token.clone();
                let namespace = crd.metadata.namespace.as_ref().unwrap().clone();
                let port_name = crd.name_any();

                let hash_key = format!("{}.{}.{}", network, version, token);
                let consumer = Consumer::new(namespace, port_name, token);

                consumers.insert(hash_key, consumer);
            }
        }
        self.state.write().await.consumers = consumers;
    }
}

#[async_trait]
impl BackgroundService for AuthBackgroundService {
    async fn start(&self, mut _shutdown: ShutdownWatch) {
        let client = Client::try_default()
            .await
            .expect("failed to create kube client");

        let api = Api::<CardanoNodePort>::all(client.clone());
        self.update_auth(api.clone()).await;

        let stream = watcher::watcher(api.clone(), Config::default()).touched_objects();
        pin!(stream);

        loop {
            let result = stream.try_next().await;
            if let Err(err) = result {
                error!(error = err.to_string(), "fail crd auth watcher");
                continue;
            }

            self.update_auth(api.clone()).await;
        }
    }
}
