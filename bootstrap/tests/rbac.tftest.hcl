mock_provider "kubernetes" {}

# Only the operator and proxy carry a token, each bound to exactly the rules
# its code needs; everything else in the namespace runs without one.

run "feature_roles_are_exact" {
  command = plan

  module {
    source = "./feature"
  }

  variables {
    namespace          = "test-namespace"
    api_key_salt       = "test"
    extension_name     = "test"
    dns_zone           = "demeter.run"
    operator_image_tag = "test"
  }

  assert {
    condition = jsonencode([
      for r in kubernetes_cluster_role_v1.operator.rule : [r.api_groups, r.resources, r.verbs]
      ]) == jsonencode([
      [["demeter.run"], ["cardanonodeports"], ["get", "list", "watch", "patch"]],
      [["demeter.run"], ["cardanonodeports/status"], ["patch"]],
    ])
    error_message = "the operator ClusterRole must grant exactly cardanonodeports get/list/watch/patch and cardanonodeports/status patch"
  }

  assert {
    condition = jsonencode([
      for r in kubernetes_cluster_role_v1.proxy.rule : [r.api_groups, r.resources, r.verbs]
      ]) == jsonencode([
      [["demeter.run"], ["cardanonodeports"], ["get", "list", "watch"]],
    ])
    error_message = "the proxy ClusterRole must grant exactly cardanonodeports get/list/watch"
  }

  assert {
    condition = (
      kubernetes_cluster_role_binding_v1.operator.role_ref[0].name == "test-namespace-operator" &&
      length(kubernetes_cluster_role_binding_v1.operator.subject) == 1 &&
      kubernetes_cluster_role_binding_v1.operator.subject[0].kind == "ServiceAccount" &&
      kubernetes_cluster_role_binding_v1.operator.subject[0].name == "operator" &&
      kubernetes_cluster_role_binding_v1.operator.subject[0].namespace == "test-namespace"
    )
    error_message = "the operator ClusterRole must be bound only to the operator service account"
  }

  assert {
    condition = (
      kubernetes_cluster_role_binding_v1.proxy.role_ref[0].name == "test-namespace-proxy" &&
      length(kubernetes_cluster_role_binding_v1.proxy.subject) == 1 &&
      kubernetes_cluster_role_binding_v1.proxy.subject[0].kind == "ServiceAccount" &&
      kubernetes_cluster_role_binding_v1.proxy.subject[0].name == "proxy" &&
      kubernetes_cluster_role_binding_v1.proxy.subject[0].namespace == "test-namespace"
    )
    error_message = "the proxy ClusterRole must be bound only to the proxy service account"
  }

  assert {
    condition     = kubernetes_default_service_account_v1.default.automount_service_account_token == false
    error_message = "the namespace default service account must not automount a token"
  }

  assert {
    condition     = kubernetes_deployment_v1.operator.spec[0].template[0].spec[0].service_account_name == "operator"
    error_message = "the operator must run as the operator service account"
  }

  assert {
    condition     = output.proxy_service_account_name == "proxy"
    error_message = "the feature module must hand the proxy service account name to the proxy modules"
  }
}

run "proxy_runs_as_given_account" {
  command = plan

  module {
    source = "./proxy"
  }

  variables {
    namespace            = "test-namespace"
    proxy_image_tag      = "test"
    instances_namespace  = "test-namespace"
    service_account_name = "proxy"
    extension_name       = "test"
    healthcheck_port     = 31789
    cloud_provider       = "aws"
  }

  assert {
    condition     = kubernetes_deployment_v1.node_proxy.spec[0].template[0].spec[0].service_account_name == "proxy"
    error_message = "the proxy must run as the service account it is given"
  }
}

run "instance_pods_carry_no_token" {
  command = plan

  module {
    source = "./instance"
  }

  variables {
    namespace      = "test-namespace"
    node_image     = "ghcr.io/blinklabs-io/cardano-node"
    node_image_tag = "11.0.1"
    network        = "mainnet"
    salt           = "a"
    release        = "pool"
    magic          = 764824073
    node_version   = "11.0.1"
  }

  assert {
    condition     = kubernetes_stateful_set_v1.node.spec[0].template[0].spec[0].automount_service_account_token == false
    error_message = "node instance pods must not automount a service account token"
  }
}
