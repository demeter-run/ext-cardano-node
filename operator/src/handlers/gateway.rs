use kube::{core::ObjectMeta, Client, CustomResourceExt, Resource, ResourceExt};
use serde::Deserialize;
use serde_json::{json, Value as JsonValue};
use tracing::info;

use crate::{
    cardano_node_service_name, create_resource, get_config, get_resource, patch_resource,
    patch_resource_status, reference_grant, tls_route, CardanoNodePort, CardanoNodePortStatus,
    Error,
};

pub async fn handle_tls_route(client: Client, crd: &CardanoNodePort) -> Result<(), Error> {
    let namespace = crd.namespace().unwrap();
    let name = format!("cardano-node-{}", crd.name_any());
    let hostname = build_host(&crd.name_any(), &project_name(&namespace));
    let tls_route = tls_route();

    let result = get_resource(client.clone(), &namespace, &tls_route, &name).await?;

    let cardano_node_service = cardano_node_service_name(&crd.spec.network, &crd.spec.version);
    let (metadata, data, raw) = build_route(&name, &hostname, crd, &cardano_node_service)?;

    if result.is_some() {
        info!(resource = crd.name_any(), "Updating tls route");
        patch_resource(client.clone(), &namespace, tls_route, &name, raw).await?;
    } else {
        info!(resource = crd.name_any(), "Creating tls route");
        create_resource(client.clone(), &namespace, tls_route, metadata, data).await?;
    }

    let status: CardanoNodePortStatus = CardanoNodePortStatus {
        endpoint_url: hostname,
    };

    patch_resource_status(
        client.clone(),
        &namespace,
        CardanoNodePort::api_resource(),
        &crd.name_any(),
        serde_json::to_value(status)?,
    )
    .await?;

    Ok(())
}

pub async fn handle_reference_grant(client: Client, crd: &CardanoNodePort) -> Result<(), Error> {
    let config = get_config();
    let namespace = crd.namespace().unwrap();
    let name = format!("{}-{}-tls", namespace, crd.name_any());
    let reference_grant = reference_grant();
    let cardano_node_service = cardano_node_service_name(&crd.spec.network, &crd.spec.version);

    let result = get_resource(client.clone(), &config.namespace, &reference_grant, &name).await?;

    let (metadata, data, raw) = build_grant(&name, &namespace, &cardano_node_service)?;

    if result.is_some() {
        info!(resource = crd.name_any(), "Updating reference grant");
        patch_resource(
            client.clone(),
            &config.namespace,
            reference_grant,
            &name,
            raw,
        )
        .await?;
    } else {
        info!(resource = crd.name_any(), "Creating reference grant");
        create_resource(
            client.clone(),
            &config.namespace,
            reference_grant,
            metadata,
            data,
        )
        .await?;
    }
    Ok(())
}

fn build_route(
    name: &str,
    hostname: &str,
    owner: &CardanoNodePort,
    private_dns_service_name: &str,
) -> Result<(ObjectMeta, JsonValue, JsonValue), Error> {
    let config = get_config();
    let tls_route = tls_route();

    let metadata = ObjectMeta::deserialize(&json!({
      "name": name,
      "labels": {
        "demeter.run/instance": name,
        "demeter.run/tenancy": "cluster",
        "demeter.run/kind": "proxy.v0.port",
      },
      "ownerReferences": [
        {
          "apiVersion": CardanoNodePort::api_version(&()).to_string(),
          "kind": CardanoNodePort::kind(&()).to_string(),
          "name": owner.name_any(),
          "uid": owner.uid()
        }
      ]
    }))?;

    let data = json!({
      "spec": {
        "hostnames": [hostname],
        "parentRefs": [
          {
              "name": "demeter",
              "namespace": "demeter-system",
              "kind": "Gateway",
              "port": config.node_port,
          },
        ],
        "rules": [
          {
            "backendRefs": [
              {
                "kind": "Service",
                "name": private_dns_service_name,
                "port": config.node_port,
                "namespace": config.namespace
              }
            ]
          }
        ]
      }
    });

    let raw = json!({
      "apiVersion": tls_route.api_version,
      "kind": tls_route.kind,
      "metadata": metadata,
      "spec": data["spec"]
    });

    Ok((metadata, data, raw))
}

fn build_grant(
    name: &str,
    namespace: &str,
    private_dns_service_name: &str,
) -> Result<(ObjectMeta, JsonValue, JsonValue), Error> {
    let reference_grant = reference_grant();
    let tls_route = tls_route();

    let metadata = ObjectMeta::deserialize(&json!({
      "name": name,
    }))?;

    let data = json!({
      "spec": {
        "from": [
              {
                  "group": tls_route.group,
                  "kind": tls_route.kind,
                  "namespace": namespace,
              },
            ],
        "to": [
            {
                "group": "",
                "kind": "Service",
                "name": private_dns_service_name,
            },
        ],
      }
    });

    let raw = json!({
      "apiVersion": reference_grant.api_version,
      "kind": reference_grant.kind,
      "metadata": metadata,
      "spec": data["spec"]
    });

    Ok((metadata, data, raw))
}

fn build_host(name: &str, project: &str) -> String {
    let config = get_config();
    format!("{}-{}.{}", name, project, config.dns_zone)
}

fn project_name(namespace: &str) -> String {
    namespace.split_once('-').unwrap().1.to_string()
}
