locals {
  custom_arguments = [
    "run",
    "--config",
    "/configuration/config.json",
    "--topology",
    "/configuration/topology.json",
    "--database-path",
    "/data/db",
    "--socket-path",
    "/ipc/node.socket",
    "--port",
    "3000"
  ]
  default_arguments = [
    "run",
    "--database-path",
    "/data/db",
    "--socket-path",
    "/ipc/node.socket",
    "--port",
    "3000"
  ]
  arguments = var.network == "vector-testnet" ? [] : var.is_custom == true ? local.custom_arguments : local.default_arguments

  n2n_port_name = var.is_relay == true ? "n2n-${var.network}" : "n2n"
}


resource "kubernetes_config_map" "proxy-config" {
  metadata {
    namespace = var.namespace
    name      = "proxy-${var.network}-${var.salt}"
  }

  data = {
    "nginx.conf" = "${file("${path.module}/nginx.conf")}"
  }
}

resource "kubernetes_stateful_set_v1" "node" {
  wait_for_rollout = false

  metadata {
    namespace = var.namespace
    name      = "node-${var.network}-${var.salt}"
    labels = {
      network      = var.network
      release      = var.release
      salt         = var.salt
      role         = "node"
      node-version = var.node_version
    }
  }

  spec {
    replicas = var.replicas

    service_name = "nodes-${var.salt}"

    selector {
      match_labels = {
        network = var.network
        release = var.release
        salt    = var.salt
        role    = "node"
      }
    }

    volume_claim_template {
      metadata {
        name = "data"
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = var.storage_class_name
        resources {
          requests = {
            storage = var.storage_size
          }
        }
      }
    }

    template {
      metadata {
        labels = {
          network      = var.network
          release      = var.release
          salt         = var.salt
          sync         = var.sync_status
          node-version = var.node_version
          role         = "node"
        }
      }

      spec {
        dynamic "affinity" {
          for_each = var.topology_zone != null ? toset([1]) : toset([])

          content {
            node_affinity {
              required_during_scheduling_ignored_during_execution {
                node_selector_term {
                  match_expressions {
                    key      = "topology.kubernetes.io/zone"
                    operator = "In"
                    values   = [var.topology_zone]
                  }
                }
              }
            }
          }
        }

        toleration {
          effect   = "NoSchedule"
          key      = "demeter.run/compute-profile"
          operator = "Equal"
          value    = var.compute_profile
        }

        toleration {
          effect   = "NoSchedule"
          key      = "demeter.run/compute-arch"
          operator = "Equal"
          value    = var.compute_arch
        }

        toleration {
          effect   = "NoSchedule"
          key      = "demeter.run/availability-sla"
          operator = "Equal"
          value    = var.availability_sla
        }

        volume {
          name = "ipc"
          empty_dir {}
        }

        volume {
          name = "proxy-config"
          config_map {
            name = "proxy-${var.network}-${var.salt}"
          }
        }

        dynamic "volume" {
          for_each = var.is_custom == true ? toset([1]) : toset([])

          content {
            name = "network-config"
            config_map {
              name = "configs-${var.network}-${var.salt}"
            }
          }
        }

        volume {
          name = "node-readiness"
          config_map {
            name         = "node-readiness"
            default_mode = "0500"
          }
        }

        container {
          image = "${var.node_image}:${var.node_image_tag}"
          name  = "main"

          args = local.arguments

          env {
            name  = "CARDANO_NETWORK"
            value = var.network
          }

          env {
            name  = "RESTORE_SNAPSHOT"
            value = var.restore
          }

          env {
            name  = "CARDANO_NODE_SOCKET_PATH"
            value = "/ipc/node.socket"
          }

          env {
            name  = "CARDANO_NODE_NETWORK_ID"
            value = var.magic
          }

          dynamic "env" {
            for_each = var.network == "vector-testnet" ? toset([1]) : toset([])

            content {
              name  = "PORT"
              value = "3000"
            }
          }

          dynamic "env" {
            for_each = var.network == "vector-testnet" ? toset([1]) : toset([])
            content {
              name  = "NETWORK"
              value = "testnet"
            }
          }

          resources {
            limits   = var.node_resources.limits
            requests = var.node_resources.requests
          }

          port {
            name           = local.n2n_port_name
            container_port = 3000
          }

          port {
            name           = "metrics"
            container_port = 12798
          }

          volume_mount {
            mount_path = "/data"
            name       = "data"
          }

          volume_mount {
            mount_path = "/ipc"
            name       = "ipc"
          }

          volume_mount {
            mount_path = "/probes"
            name       = "node-readiness"
          }

          dynamic "volume_mount" {
            for_each = var.is_custom == true ? toset([1]) : toset([])

            content {
              mount_path = "/configuration"
              name       = "network-config"
            }
          }

          dynamic "readiness_probe" {
            for_each = var.network != "vector-testnet" ? toset([1]) : toset([])

            content {
              initial_delay_seconds = 20
              exec {
                command = ["/probes/readiness.sh"]
              }
            }
          }
        }

        container {
          name  = "nginx"
          image = "nginx"

          resources {
            limits = {
              memory = "100Mi"
            }
            requests = {
              cpu    = "10m"
              memory = "100Mi"
            }
          }

          port {
            name           = "n2c"
            container_port = 3307
          }

          volume_mount {
            mount_path = "/ipc"
            name       = "ipc"
          }

          volume_mount {
            mount_path = "/etc/nginx"
            name       = "proxy-config"
          }
        }
      }
    }
  }
}
