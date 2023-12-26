use std::fmt::{self, Display, Formatter};

use prometheus::Registry;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum Error {
    #[error("Kube Error: {0}")]
    KubeError(#[source] kube::Error),
}
impl Error {
    pub fn metric_label(&self) -> String {
        format!("{self:?}").to_lowercase()
    }
}
impl From<kube::Error> for Error {
    fn from(value: kube::Error) -> Self {
        Error::KubeError(value)
    }
}

#[derive(Clone, Default)]
pub struct State {
    registry: Registry,
    pub metrics: Metrics,
}
impl State {
    pub fn new() -> Self {
        let registry = Registry::default();
        let metrics = Metrics::default().register(&registry).unwrap();
        Self { registry, metrics }
    }

    pub fn metrics_collected(&self) -> Vec<prometheus::proto::MetricFamily> {
        self.registry.gather()
    }
}

#[derive(Debug, Clone, Deserialize, Serialize, JsonSchema)]
pub enum Network {
    #[serde(rename = "mainnet")]
    Mainnet,
    #[serde(rename = "preprod")]
    Preprod,
    #[serde(rename = "preview")]
    Preview,
    #[serde(rename = "sanchonet")]
    Sanchonet,
}
impl Display for Network {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        match self {
            Network::Mainnet => write!(f, "mainnet"),
            Network::Preprod => write!(f, "preprod"),
            Network::Preview => write!(f, "preview"),
            Network::Sanchonet => write!(f, "sanchonet"),
        }
    }
}

pub type Result<T, E = Error> = std::result::Result<T, E>;

pub mod controller;
pub use crate::controller::*;

pub mod metrics;
pub use metrics::*;

mod config;
pub use config::*;
