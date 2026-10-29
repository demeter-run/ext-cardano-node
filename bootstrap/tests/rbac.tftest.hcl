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
      length(kubernetes_cluster_role_v1.operator.aggregation_rule) == 0 &&
      length(kubernetes_cluster_role_v1.proxy.aggregation_rule) == 0
    )
    error_message = "the operator and proxy ClusterRoles must not aggregate rules from other roles"
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
    condition = (
      kubernetes_service_account_v1.operator.automount_service_account_token == false &&
      kubernetes_service_account_v1.proxy.automount_service_account_token == false
    )
    error_message = "the operator and proxy service accounts must not automount a token; their pod specs opt in"
  }

  assert {
    condition     = kubernetes_deployment_v1.operator.spec[0].template[0].spec[0].automount_service_account_token == true
    error_message = "the operator pod must mount its service account token"
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

  assert {
    condition     = kubernetes_deployment_v1.node_proxy.spec[0].template[0].spec[0].automount_service_account_token == true
    error_message = "the proxy pod must mount its service account token"
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

# The census runs read the bootstrap source, excluding tests/ and .terraform/:
# every .tf, .tf.json, .json, .yaml, .yml, .tftpl and .tpl file. They catch
# typed resources (quoted or bare labels, HCL or JSON syntax) and manifest
# kinds, but not grants or accounts that reach the namespace from outside this
# tree (a Helm chart, a remote module, the caller), nor kinds assembled from
# expressions rather than written as literals.

# Every role binding in the bootstrap tree is one of the two above, so no other
# grant can reach the operator or proxy account.
run "only_the_two_bindings_exist" {
  command = plan

  module {
    source = "./tests/census"
  }

  variables {
    patterns = [
      "resource\\s+\"?(kubernetes_(?:cluster_)?role_binding(?:_v1)?)\"?\\s+\"?([\\w-]+)\"?",
      "\"(kubernetes_(?:cluster_)?role_binding(?:_v1)?)\"\\s*:",
      "kind\"?\\s*[=:]\\s*\"?((?:Cluster)?RoleBinding)\\b",
    ]
  }

  assert {
    condition = jsonencode(output.matches) == jsonencode([
      "feature/rbac.tf:kubernetes_cluster_role_binding_v1 operator",
      "feature/rbac.tf:kubernetes_cluster_role_binding_v1 proxy",
    ])
    error_message = "bootstrap must declare no role binding beyond the operator and proxy ClusterRoleBindings"
  }
}

# Only the operator and proxy pods opt into a token. No account automounts one,
# no other account or token Secret exists, and no pod projects a token itself.
run "only_the_operator_and_proxy_pods_carry_a_token" {
  command = plan

  module {
    source = "./tests/census"
  }

  variables {
    patterns = [
      "(automount_service_account_token|automountServiceAccountToken)\"?\\s*[=:]\\s*([^\\s,}]+)",
      "resource\\s+\"?(kubernetes_(?:default_)?service_account(?:_v1)?)\"?\\s+\"?([\\w-]+)\"?",
      "\"(kubernetes_(?:default_)?service_account(?:_v1)?)\"\\s*:",
      "kind\"?\\s*[=:]\\s*\"?(ServiceAccount)\\b",
      "(service_account_token\\s*\\{|serviceAccountToken|service-account-token)",
    ]
  }

  assert {
    condition = jsonencode(output.matches) == jsonencode([
      "feature/operator.tf:automount_service_account_token true",
      "feature/rbac.tf:automount_service_account_token false",
      "feature/rbac.tf:automount_service_account_token false",
      "feature/rbac.tf:automount_service_account_token false",
      "feature/rbac.tf:kubernetes_default_service_account_v1 default",
      "feature/rbac.tf:kubernetes_service_account_v1 operator",
      "feature/rbac.tf:kubernetes_service_account_v1 proxy",
      # The two binding subjects.
      "feature/rbac.tf:ServiceAccount",
      "feature/rbac.tf:ServiceAccount",
      "instance/node.tf:automount_service_account_token false",
      "proxy/deployment.tf:automount_service_account_token true",
    ])
    error_message = "only the operator and proxy pod specs may mount a token, and only the three known service accounts may exist"
  }
}

# The token census above only sees automount where it is written out. A typed
# pod spec that leaves it out plans as true, and a pod-level true overrides the
# account's false, so every typed pod-bearing resource must be one of the three
# whose automount is asserted directly: the operator and proxy Deployments and
# the node StatefulSet. No manifest may carry a pod-bearing kind either.
run "only_the_three_known_workloads_exist" {
  command = plan

  module {
    source = "./tests/census"
  }

  variables {
    patterns = [
      "resource\\s+\"?(kubernetes_(?:deployment|stateful_set|daemon_set|replica_set|replication_controller|job|cron_job|pod)(?:_v[12])?)\"?\\s+\"?([\\w-]+)\"?",
      "\"(kubernetes_(?:deployment|stateful_set|daemon_set|replica_set|replication_controller|job|cron_job|pod)(?:_v[12])?)\"\\s*:",
      "kind\"?\\s*[=:]\\s*\"?(Pod|Deployment|StatefulSet|DaemonSet|ReplicaSet|ReplicationController|Job|CronJob)\\b",
    ]
  }

  assert {
    condition = jsonencode(output.matches) == jsonencode([
      "feature/operator.tf:kubernetes_deployment_v1 operator",
      "instance/node.tf:kubernetes_stateful_set_v1 node",
      "proxy/deployment.tf:kubernetes_deployment_v1 node_proxy",
    ])
    error_message = "bootstrap must declare no pod-bearing workload beyond the operator, proxy and node instance ones, whose automount settings are asserted directly"
  }
}

run "root_wires_proxy_account_to_both_colors" {
  command = plan

  variables {
    namespace                       = "test-namespace"
    operator_image_tag              = "test"
    api_key_salt                    = "test"
    proxy_blue_image_tag            = "test"
    proxy_blue_instances_namespace  = "test-namespace"
    proxy_blue_healthcheck_port     = 31789
    proxy_green_image_tag           = "test"
    proxy_green_instances_namespace = "test-namespace"
    proxy_green_healthcheck_port    = 32171
    instances                       = {}
    services                        = {}
  }

  assert {
    condition = (
      module.node_v1_proxy_blue.service_account_name == "proxy" &&
      module.node_v1_proxy_green.service_account_name == "proxy"
    )
    error_message = "both proxy colors must run as the proxy service account"
  }
}
