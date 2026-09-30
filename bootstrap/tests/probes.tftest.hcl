mock_provider "kubernetes" {}

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
  services                        = {}
}

run "tip_age_is_opt_in" {
  command = plan

  variables {
    instances = {
      mainnet-a = {
        node_image      = "ghcr.io/blinklabs-io/cardano-node"
        image_tag       = "11.0.1"
        network         = "mainnet"
        salt            = "a"
        release         = "default"
        magic           = 764824073
        node_version    = "11.0.1"
        replicas        = 1
        readiness_probe = { period_seconds = 120 }
        liveness_probe  = { period_seconds = 120 }
        startup_probe   = { period_seconds = 120 }
      }
    }
  }

  assert {
    condition = alltrue([
      for command in values(module.instances["mainnet-a"].probe_commands) : command == tolist(["/probes/readiness.sh"])
    ])
    error_message = "a probe without max_tip_age_seconds must run the script with no argument"
  }
}

run "tip_age_is_passed_per_probe" {
  command = plan

  variables {
    instances = {
      mainnet-a = {
        node_image      = "ghcr.io/blinklabs-io/cardano-node"
        image_tag       = "11.0.1"
        network         = "mainnet"
        salt            = "a"
        release         = "default"
        magic           = 764824073
        node_version    = "11.0.1"
        replicas        = 1
        readiness_probe = { max_tip_age_seconds = 180 }
        liveness_probe  = { max_tip_age_seconds = 900 }
        startup_probe   = {}
      }
    }
  }

  assert {
    condition     = module.instances["mainnet-a"].probe_commands["readiness"] == tolist(["/probes/readiness.sh", "180"])
    error_message = "the readiness probe must pass its max_tip_age_seconds to the script"
  }

  assert {
    condition     = module.instances["mainnet-a"].probe_commands["liveness"] == tolist(["/probes/readiness.sh", "900"])
    error_message = "the liveness probe must pass its own max_tip_age_seconds to the script"
  }

  assert {
    condition     = module.instances["mainnet-a"].probe_commands["startup"] == tolist(["/probes/readiness.sh"])
    error_message = "a probe without max_tip_age_seconds must not inherit another probe's value"
  }
}

run "prime_testnet_keeps_socket_check" {
  command = plan

  variables {
    instances = {
      prime-testnet-a = {
        node_image      = "ghcr.io/blinklabs-io/cardano-node"
        image_tag       = "11.0.1"
        network         = "prime-testnet"
        salt            = "a"
        release         = "default"
        magic           = 3311
        node_version    = "11.0.1"
        replicas        = 1
        readiness_probe = { max_tip_age_seconds = 180 }
      }
    }
  }

  assert {
    condition     = module.instances["prime-testnet-a"].probe_commands["readiness"] == tolist(["test", "-S", "/ipc/node.socket"])
    error_message = "prime-testnet must keep its socket-only probe"
  }
}

run "mesh_peer_service_publishes_not_ready_addresses" {
  command = plan

  variables {
    instances = {
      mainnet-mesh-a = {
        node_image   = "ghcr.io/blinklabs-io/cardano-node"
        image_tag    = "11.0.1"
        network      = "mainnet"
        salt         = "a"
        release      = "mesh"
        magic        = 764824073
        node_version = "11.0.1"
        replicas     = 1
        topology = {
          local_roots = [
            { address = "node-mainnet-b-0.nodes-b.test-namespace.svc.cluster.local", port = 3000 },
          ]
        }
      }
    }
  }

  assert {
    condition     = module.instances["mainnet-mesh-a"].peer_service.publish_not_ready_addresses == true
    error_message = "the mesh peer Service must keep resolving a node whose readiness probe fails"
  }
}
