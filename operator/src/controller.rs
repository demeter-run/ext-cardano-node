use futures::StreamExt;
use kube::{
    api::ListParams,
    runtime::{controller::Action, watcher::Config as WatcherConfig, Controller},
    Api, Client, CustomResource, ResourceExt,
};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::{sync::Arc, time::Duration};
use tracing::{error, info};

use crate::{Error, Metrics, Network, Result, State};

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
        {"name": "Version", "jsonPath": ".spec.version", "type": "number"},
        {"name": "Endpoint URL", "jsonPath": ".status.endpointUrl",  "type": "string"}
    "#)]
#[serde(rename_all = "camelCase")]
pub struct CardanoNodePortSpec {
    pub network: Network,
    pub version: u8,
}

#[derive(Deserialize, Serialize, Clone, Default, Debug, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct CardanoNodePortStatus {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub endpoint_url: Option<String>,
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
    let _client = ctx.client.clone();
    let _namespace = crd.namespace().unwrap();

    info!(name = crd.name_any(), "reconcile");

    Ok(Action::await_change())
}

fn error_policy(crd: Arc<CardanoNodePort>, err: &Error, ctx: Arc<Context>) -> Action {
    ctx.metrics.reconcile_failure(&crd, err);
    Action::requeue(Duration::from_secs(5))
}

pub async fn run(state: Arc<State>) {
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
