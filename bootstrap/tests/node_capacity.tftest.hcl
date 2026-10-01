mock_provider "kubernetes" {}

# The four node-capacity inputs are opt-in: an instance or Service that does
# not set them must render as it did before they existed.

run "grace_period_is_rendered_when_set" {
  command = plan

  module {
    source = "./instance"
  }

  variables {
    namespace                        = "test-namespace"
    node_image                       = "ghcr.io/blinklabs-io/cardano-node"
    node_image_tag                   = "11.0.1"
    network                          = "mainnet"
    salt                             = "a"
    release                          = "pool"
    magic                            = 764824073
    node_version                     = "11.0.1"
    termination_grace_period_seconds = 600
  }

  assert {
    condition     = kubernetes_stateful_set_v1.node.spec[0].template[0].spec[0].termination_grace_period_seconds == 600
    error_message = "a set termination_grace_period_seconds must be rendered on the pod spec"
  }
}

run "grace_period_is_left_to_kubernetes_when_unset" {
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
    condition     = kubernetes_stateful_set_v1.node.spec[0].template[0].spec[0].termination_grace_period_seconds == null
    error_message = "an unset termination_grace_period_seconds must leave the Kubernetes default"
  }
}

run "grace_period_must_be_a_positive_whole_number" {
  command = plan

  module {
    source = "./instance"
  }

  variables {
    namespace                        = "test-namespace"
    node_image                       = "ghcr.io/blinklabs-io/cardano-node"
    node_image_tag                   = "11.0.1"
    network                          = "mainnet"
    salt                             = "a"
    release                          = "pool"
    magic                            = 764824073
    node_version                     = "11.0.1"
    termination_grace_period_seconds = 0
  }

  expect_failures = [var.termination_grace_period_seconds]
}

run "spread_hosts_adds_a_preferred_anti_affinity" {
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
    spread_hosts   = true
    node_affinity = {
      required_during_scheduling_ignored_during_execution = {
        node_selector_term = [{
          match_expressions = [{
            key      = "demeter.run/compute-profile"
            operator = "In"
            values   = ["mem-intensive"]
          }]
        }]
      }
    }
  }

  assert {
    condition     = length(kubernetes_stateful_set_v1.node.spec[0].template[0].spec[0].affinity[0].pod_anti_affinity[0].required_during_scheduling_ignored_during_execution) == 0
    error_message = "the anti-affinity must not be required: the cluster has no autoscaler"
  }

  assert {
    condition     = kubernetes_stateful_set_v1.node.spec[0].template[0].spec[0].affinity[0].pod_anti_affinity[0].preferred_during_scheduling_ignored_during_execution[0].weight == 100
    error_message = "the preferred anti-affinity term must have weight 100"
  }

  assert {
    condition     = kubernetes_stateful_set_v1.node.spec[0].template[0].spec[0].affinity[0].pod_anti_affinity[0].preferred_during_scheduling_ignored_during_execution[0].pod_affinity_term[0].topology_key == "kubernetes.io/hostname"
    error_message = "the anti-affinity must spread across hosts"
  }

  assert {
    condition     = kubernetes_stateful_set_v1.node.spec[0].template[0].spec[0].affinity[0].pod_anti_affinity[0].preferred_during_scheduling_ignored_during_execution[0].pod_affinity_term[0].label_selector[0].match_labels == tomap({ role = "node", network = "mainnet" })
    error_message = "the anti-affinity must select nodes of the instance's network"
  }

  assert {
    condition     = kubernetes_stateful_set_v1.node.spec[0].template[0].spec[0].affinity[0].node_affinity[0].required_during_scheduling_ignored_during_execution[0].node_selector_term[0].match_expressions[0].values == toset(["mem-intensive"])
    error_message = "spread_hosts must keep the existing node affinity"
  }
}

run "spread_hosts_alone_renders_no_node_affinity" {
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
    spread_hosts   = true
  }

  assert {
    condition     = length(kubernetes_stateful_set_v1.node.spec[0].template[0].spec[0].affinity[0].node_affinity) == 0
    error_message = "spread_hosts without a node affinity must not add an empty one"
  }

  assert {
    condition     = length(kubernetes_stateful_set_v1.node.spec[0].template[0].spec[0].affinity[0].pod_anti_affinity) == 1
    error_message = "spread_hosts must render the anti-affinity on its own"
  }
}

run "no_anti_affinity_without_spread_hosts" {
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
    node_affinity = {
      required_during_scheduling_ignored_during_execution = {
        node_selector_term = [{
          match_expressions = [{
            key      = "demeter.run/compute-profile"
            operator = "In"
            values   = ["mem-intensive"]
          }]
        }]
      }
    }
  }

  assert {
    condition     = length(kubernetes_stateful_set_v1.node.spec[0].template[0].spec[0].affinity[0].pod_anti_affinity) == 0
    error_message = "an instance without spread_hosts must not get an anti-affinity"
  }

  assert {
    condition     = length(kubernetes_stateful_set_v1.node.spec[0].template[0].spec[0].affinity[0].node_affinity) == 1
    error_message = "an instance without spread_hosts must keep its node affinity"
  }
}

run "no_affinity_block_by_default" {
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
    condition     = length(kubernetes_stateful_set_v1.node.spec[0].template[0].spec[0].affinity) == 0
    error_message = "an instance with neither node affinity nor spread_hosts must render no affinity"
  }
}

run "headless_service_publishes_ready_pods_only" {
  command = plan

  module {
    source = "./service"
  }

  variables {
    name         = "node-mainnet-pool"
    namespace    = "test-namespace"
    network      = "mainnet"
    release      = "pool"
    node_version = "11.0.1"
    headless     = true
  }

  assert {
    condition     = kubernetes_service_v1.well_known_service.spec[0].cluster_ip == "None"
    error_message = "a headless Service must have cluster_ip None"
  }

  assert {
    condition     = kubernetes_service_v1.well_known_service.spec[0].publish_not_ready_addresses == false
    error_message = "a headless pool Service must not publish not-ready addresses"
  }

  assert {
    condition     = kubernetes_service_v1.well_known_service.spec[0].selector == tomap({ role = "node", network = "mainnet", "node-version" = "11.0.1" })
    error_message = "a headless Service must keep the usual selector"
  }

  assert {
    condition     = toset([for port in kubernetes_service_v1.well_known_service.spec[0].port : "${port.name}:${port.port}"]) == toset(["n2c:3307", "n2n:3000"])
    error_message = "a headless Service must keep the n2c and n2n ports"
  }

  assert {
    condition     = length(kubernetes_pod_disruption_budget_v1.pool) == 0
    error_message = "no PodDisruptionBudget without pdb_max_unavailable"
  }
}

run "service_is_unchanged_by_default" {
  command = plan

  module {
    source = "./service"
  }

  variables {
    namespace    = "test-namespace"
    network      = "mainnet"
    release      = "stable"
    node_version = "11.0.1"
    active_salt  = "a"
  }

  assert {
    condition     = kubernetes_service_v1.well_known_service.spec[0].publish_not_ready_addresses == null
    error_message = "a Service without headless must not set publish_not_ready_addresses"
  }

  assert {
    condition     = length(kubernetes_pod_disruption_budget_v1.pool) == 0
    error_message = "no PodDisruptionBudget without pdb_max_unavailable"
  }
}

run "pdb_follows_the_service" {
  command = plan

  module {
    source = "./service"
  }

  variables {
    name                = "node-mainnet-pool"
    namespace           = "test-namespace"
    network             = "mainnet"
    release             = "pool"
    node_version        = "11.0.1"
    active_salt         = "a"
    headless            = true
    pdb_max_unavailable = 1
  }

  assert {
    condition     = kubernetes_pod_disruption_budget_v1.pool[0].metadata[0].name == "node-mainnet-pool"
    error_message = "the PodDisruptionBudget must be named after the Service"
  }

  assert {
    condition     = kubernetes_pod_disruption_budget_v1.pool[0].spec[0].max_unavailable == "1"
    error_message = "the PodDisruptionBudget must carry pdb_max_unavailable"
  }

  assert {
    condition     = kubernetes_pod_disruption_budget_v1.pool[0].spec[0].selector[0].match_labels == kubernetes_service_v1.well_known_service.spec[0].selector
    error_message = "the PodDisruptionBudget must select the Service's pods"
  }
}

run "root_passes_the_new_inputs_through" {
  command = plan

  variables {
    namespace                       = "test-namespace"
    operator_image_tag              = "test"
    api_key_salt                    = "test"
    proxy_blue_image_tag            = "test"
    proxy_blue_instances_namespace  = "test-namespace"
    proxy_green_image_tag           = "test"
    proxy_green_instances_namespace = "test-namespace"

    instances = {
      mainnet-pool-a = {
        node_image                       = "ghcr.io/blinklabs-io/cardano-node"
        image_tag                        = "11.0.1"
        network                          = "mainnet"
        salt                             = "a"
        release                          = "pool"
        magic                            = 764824073
        node_version                     = "11.0.1"
        replicas                         = 1
        termination_grace_period_seconds = 600
        spread_hosts                     = true
      }
    }

    services = {
      mainnet-pool = {
        name                = "node-mainnet-pool"
        network             = "mainnet"
        release             = "pool"
        node_version        = "11.0.1"
        active_salt         = ""
        headless            = true
        pdb_max_unavailable = 1
      }
    }
  }
}
