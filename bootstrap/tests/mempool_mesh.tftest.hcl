mock_provider "kubernetes" {}

run "four_node_mainnet_mesh" {
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
    services                        = {}

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
            { address = "node-mainnet-c-0.nodes-c.test-namespace.svc.cluster.local", port = 3000 },
            { address = "node-mainnet-d-0.nodes-d.test-namespace.svc.cluster.local", port = 3000 },
          ]
        }
      }
      mainnet-mesh-b = {
        node_image   = "ghcr.io/blinklabs-io/cardano-node"
        image_tag    = "11.0.1"
        network      = "mainnet"
        salt         = "b"
        release      = "mesh"
        magic        = 764824073
        node_version = "11.0.1"
        replicas     = 1
        topology = {
          local_roots = [
            { address = "node-mainnet-a-0.nodes-a.test-namespace.svc.cluster.local", port = 3000 },
            { address = "node-mainnet-c-0.nodes-c.test-namespace.svc.cluster.local", port = 3000 },
            { address = "node-mainnet-d-0.nodes-d.test-namespace.svc.cluster.local", port = 3000 },
          ]
        }
      }
      mainnet-mesh-c = {
        node_image   = "ghcr.io/blinklabs-io/cardano-node"
        image_tag    = "11.0.1"
        network      = "mainnet"
        salt         = "c"
        release      = "mesh"
        magic        = 764824073
        node_version = "11.0.1"
        replicas     = 1
        topology = {
          local_roots = [
            { address = "node-mainnet-a-0.nodes-a.test-namespace.svc.cluster.local", port = 3000 },
            { address = "node-mainnet-b-0.nodes-b.test-namespace.svc.cluster.local", port = 3000 },
            { address = "node-mainnet-d-0.nodes-d.test-namespace.svc.cluster.local", port = 3000 },
          ]
        }
      }
      mainnet-mesh-d = {
        node_image   = "ghcr.io/blinklabs-io/cardano-node"
        image_tag    = "11.0.1"
        network      = "mainnet"
        salt         = "d"
        release      = "mesh"
        magic        = 764824073
        node_version = "11.0.1"
        replicas     = 1
        topology = {
          local_roots = [
            { address = "node-mainnet-a-0.nodes-a.test-namespace.svc.cluster.local", port = 3000 },
            { address = "node-mainnet-b-0.nodes-b.test-namespace.svc.cluster.local", port = 3000 },
            { address = "node-mainnet-c-0.nodes-c.test-namespace.svc.cluster.local", port = 3000 },
          ]
        }
      }
    }
  }

  assert {
    condition     = length(keys(module.custom_configs)) == 4
    error_message = "each mesh instance must have its own topology ConfigMap"
  }

  assert {
    condition = alltrue([
      for key, instance in var.instances : (
        module.instances[key].peer_service.cluster_ip == "None" &&
        module.instances[key].peer_service.selector == {
          network = instance.network
          release = instance.release
          salt    = instance.salt
          role    = "node"
        } &&
        module.instances[key].peer_service.port == 3000
      )
    ])
    error_message = "each mesh peer Service must be headless and select exactly one node instance"
  }

  assert {
    condition = alltrue([
      for key, instance in var.instances : (
        module.custom_configs[key].topology.localRoots[0].advertise == false &&
        module.custom_configs[key].topology.localRoots[0].valency == 3 &&
        sort([for point in module.custom_configs[key].topology.localRoots[0].accessPoints : point.address]) == sort([
          for peer_key, peer in var.instances : "node-${peer.network}-${peer.salt}-0.nodes-${peer.salt}.${var.namespace}.svc.cluster.local"
          if peer_key != key
        ]) &&
        length(distinct([for point in module.custom_configs[key].topology.localRoots[0].accessPoints : point.address])) == 3 &&
        !contains([for point in module.custom_configs[key].topology.localRoots[0].accessPoints : point.address], "node-${instance.network}-${instance.salt}-0.nodes-${instance.salt}.${var.namespace}.svc.cluster.local")
      )
    ])
    error_message = "each topology must contain exactly the other three node DNS names as non-advertised local roots"
  }
}

run "topology_is_opt_in" {
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
    services                        = {}

    instances = {
      mainnet-default-a = {
        node_image   = "ghcr.io/blinklabs-io/cardano-node"
        image_tag    = "11.0.1"
        network      = "mainnet"
        salt         = "a"
        release      = "default"
        magic        = 764824073
        node_version = "11.0.1"
        replicas     = 1
      }
    }
  }

  assert {
    condition     = length(keys(module.custom_configs)) == 0
    error_message = "an instance without topology.local_roots must not receive a new ConfigMap"
  }

  assert {
    condition     = module.instances["mainnet-default-a"].peer_service == null
    error_message = "an instance without topology.local_roots must not receive a headless peer Service"
  }
}
