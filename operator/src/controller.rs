use futures::StreamExt;
use kube::{
    api::ListParams,
    runtime::{controller::Action, watcher::Config as WatcherConfig, Controller},
    Api, Client, CustomResource, CustomResourceExt, ResourceExt,
};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::{sync::Arc, time::Duration};
use tracing::{error, info};

use crate::{build_api_key, build_hostname, patch_resource_status, Error, Metrics, Result, State};

pub static CARDANO_NODE_PORT_FINALIZER: &str = "cardanonodeports.demeter.run";

#[derive(CustomResource, Deserialize, Serialize, Clone, Debug, JsonSchema)]
#[kube(
    kind = "CardanoNodePort",
    group = "demeter.run",
    version = "v1alpha1",
    namespaced
)]
#[kube(status = "CardanoNodePortStatus")]
#[kube(printcolumn = r#"
        {"name": "Network", "jsonPath": ".spec.network", "type": "string"},
        {"name": "Version", "jsonPath": ".spec.version", "type": "string"},
        {"name": "Throughput Tier", "jsonPath": ".spec.throughputTier", "type": "string"},
        {"name": "Authenticated Endpoint", "jsonPath": ".status.authenticatedEndpoint", "type": "string"},
        {"name": "Auth Token", "jsonPath": ".status.authToken", "type": "string"}
    "#)]
#[serde(rename_all = "camelCase")]
pub struct CardanoNodePortSpec {
    pub network: String,
    pub version: String,
    pub throughput_tier: String,
}

#[derive(Deserialize, Serialize, Clone, Default, Debug, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct CardanoNodePortStatus {
    pub authenticated_endpoint: String,
    pub auth_token: String,
}

struct Context {
    pub client: Client,
    pub metrics: Metrics,
}
impl Context {
    pub fn new(client: Client, metrics: Metrics) -> Self {
        Self { client, metrics }
    }
}

async fn reconcile(crd: Arc<CardanoNodePort>, ctx: Arc<Context>) -> Result<Action> {
    let key = build_api_key(&crd).await?;

    let status = CardanoNodePortStatus {
        authenticated_endpoint: build_hostname(&crd.spec.network, &crd.spec.version, &key),
        auth_token: key,
    };

    let namespace = crd.namespace().unwrap();
    let node_port = CardanoNodePort::api_resource();

    patch_resource_status(
        ctx.client.clone(),
        &namespace,
        node_port,
        &crd.name_any(),
        serde_json::to_value(status)?,
    )
    .await?;

    info!(resource = crd.name_any(), "Reconcile completed");

    Ok(Action::await_change())
}

fn error_policy(crd: Arc<CardanoNodePort>, err: &Error, ctx: Arc<Context>) -> Action {
    error!(error = err.to_string(), "reconcile failed");
    ctx.metrics.reconcile_failure(&crd, err);
    Action::requeue(Duration::from_secs(5))
}

pub async fn run(state: Arc<State>) {
    info!("listening crds running");

    let client = Client::try_default()
        .await
        .expect("failed to create kube client");

    let crds = Api::<CardanoNodePort>::all(client.clone());
    if let Err(e) = crds.list(&ListParams::default().limit(1)).await {
        error!("CRD is not queryable; {e:?}. Is the CRD installed?");
        std::process::exit(1);
    }

    let ctx = Context::new(client, state.metrics.clone());

    Controller::new(crds, WatcherConfig::default().any_semantic())
        .shutdown_on_signal()
        .run(reconcile, error_policy, Arc::new(ctx))
        .filter_map(|x| async move { std::result::Result::ok(x) })
        .for_each(|_| futures::future::ready(()))
        .await;
}
