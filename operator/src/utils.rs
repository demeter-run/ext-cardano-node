use argon2::Argon2;
use bech32::{Bech32m, Hrp};
use kube::{
    api::{Patch, PatchParams},
    core::DynamicObject,
    discovery::ApiResource,
    Api, Client, ResourceExt,
};
use serde_json::json;

use crate::{get_config, CardanoNodePort, Error};

pub async fn patch_resource_status(
    client: Client,
    namespace: &str,
    api_resource: ApiResource,
    name: &str,
    payload: serde_json::Value,
) -> Result<(), kube::Error> {
    let api: Api<DynamicObject> = Api::namespaced_with(client, namespace, &api_resource);

    let status = json!({ "status": payload });
    let patch_params = PatchParams::default();
    api.patch_status(name, &patch_params, &Patch::Merge(status))
        .await?;
    Ok(())
}

pub fn build_hostname(network: &str, version: &str, key: &str) -> String {
    let config = get_config();
    let extension_name = &config.extension_name;
    let dns_zone = &config.dns_zone;

    format!("{key}.{network}-{version}.{extension_name}.{dns_zone}")
}

pub async fn build_api_key(crd: &CardanoNodePort) -> Result<String, Error> {
    let namespace = crd.namespace().unwrap();
    let name = format!("cardano-node-auth-{}", &crd.name_any());

    let password = format!("{}{}", name, namespace).as_bytes().to_vec();

    let config = get_config();
    let salt = config.api_key_salt.as_bytes();

    let mut output = vec![0; 16];

    let argon2 = Argon2::default();
    argon2.hash_password_into(password.as_slice(), salt, &mut output)?;

    let hrp = Hrp::parse("dmtr_cnode")?;
    let with_bech = bech32::encode::<Bech32m>(hrp, output.as_slice())?;

    Ok(with_bech)
}
