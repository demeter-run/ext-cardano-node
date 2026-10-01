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
  arguments = startswith(var.network, "vector") ? [] : var.is_custom == true ? local.custom_arguments : local.default_arguments

  n2n_port_name = var.is_relay == true ? "n2n-${var.network}" : "n2n"

  default_tolerations = [
    {
      effect   = "NoSchedule"
      key      = "demeter.run/compute-profile"
      operator = "Equal"
      value    = var.compute_profile
    },
    {
      effect   = "NoSchedule"
      key      = "demeter.run/compute-arch"
      operator = "Equal"
      value    = var.compute_arch
    },
    {
      effect   = "NoSchedule"
      key      = "demeter.run/availability-sla"
      operator = "Equal"
      value    = var.availability_sla
    }
  ]

  combined_tolerations = concat(local.default_tolerations, var.tolerations)

  has_node_affinity = (
    var.node_affinity != null &&
    (
      try(length(var.node_affinity.required_during_scheduling_ignored_during_execution.node_selector_term), 0) > 0 ||
      try(length(var.node_affinity.preferred_during_scheduling_ignored_during_execution), 0) > 0
    )
  )

  spread_hosts_selector = {
    role    = "node"
    network = var.network
  }

  peer_service_selector = {
    network = var.network
    release = var.release
    salt    = var.salt
    role    = "node"
  }

  # prime-testnet only checks for the socket. Elsewhere a probe with
  # max_tip_age_seconds passes it to the script, which then also fails on a
  # stale tip.
  socket_probe_command = ["test", "-S", "/ipc/node.socket"]
  probes = {
    readiness = var.readiness_probe
    liveness  = var.liveness_probe
    startup   = var.startup_probe
  }
  probe_commands = {
    for name, probe in local.probes : name => tolist(
      var.network == "prime-testnet"
      ? local.socket_probe_command
      : concat(
        ["/probes/readiness.sh"],
        try(probe.max_tip_age_seconds, null) != null ? [tostring(probe.max_tip_age_seconds)] : []
      )
    )
  }
}

resource "kubernetes_service_v1" "peer" {
  count = var.has_local_roots ? 1 : 0

  metadata {
    namespace = var.namespace
    name      = "nodes-${var.salt}"
  }

  spec {
    cluster_ip = "None"

    # The mesh must keep resolving a peer while its readiness probe fails:
    # a missing record is cached as NXDOMAIN by the other nodes for up to
    # 15 minutes, well past the peer's recovery.
    publish_not_ready_addresses = true

    selector = local.peer_service_selector

    port {
      name     = "n2n"
      protocol = "TCP"
      port     = 3000
    }
  }
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
        termination_grace_period_seconds = var.termination_grace_period_seconds

        dynamic "affinity" {
          for_each = local.has_node_affinity || var.spread_hosts ? [1] : []
          content {
            dynamic "node_affinity" {
              for_each = local.has_node_affinity ? [var.node_affinity] : []
              content {
                dynamic "required_during_scheduling_ignored_during_execution" {
                  for_each = (
                    var.node_affinity.required_during_scheduling_ignored_during_execution != null &&
                    length(var.node_affinity.required_during_scheduling_ignored_during_execution.node_selector_term) > 0
                  ) ? [var.node_affinity.required_during_scheduling_ignored_during_execution] : []
                  content {
                    dynamic "node_selector_term" {
                      for_each = required_during_scheduling_ignored_during_execution.value.node_selector_term
                      content {
                        dynamic "match_expressions" {
                          for_each = length(node_selector_term.value.match_expressions) > 0 ? node_selector_term.value.match_expressions : []
                          content {
                            key      = match_expressions.value.key
                            operator = match_expressions.value.operator
                            values   = match_expressions.value.values
                          }
                        }
                      }
                    }
                  }
                }
                dynamic "preferred_during_scheduling_ignored_during_execution" {
                  for_each = (
                    var.node_affinity.preferred_during_scheduling_ignored_during_execution != null &&
                    length(var.node_affinity.preferred_during_scheduling_ignored_during_execution) > 0
                  ) ? var.node_affinity.preferred_during_scheduling_ignored_during_execution : []
                  content {
                    weight = preferred_during_scheduling_ignored_during_execution.value.weight

                    dynamic "preference" {
                      for_each = (
                        length(preferred_during_scheduling_ignored_during_execution.value.preference.match_expressions) > 0 ||
                        length(preferred_during_scheduling_ignored_during_execution.value.preference.match_fields) > 0
                      ) ? [preferred_during_scheduling_ignored_during_execution.value.preference] : []
                      content {
                        dynamic "match_expressions" {
                          for_each = length(preference.value.match_expressions) > 0 ? preference.value.match_expressions : []
                          content {
                            key      = match_expressions.value.key
                            operator = match_expressions.value.operator
                            values   = match_expressions.value.values
                          }
                        }
                        dynamic "match_fields" {
                          for_each = length(preference.value.match_fields) > 0 ? preference.value.match_fields : []
                          content {
                            key      = match_fields.value.key
                            operator = match_fields.value.operator
                            values   = match_fields.value.values
                          }
                        }
                      }
                    }
                  }
                }
              }
            }

            # Preferred, never required: the cluster has no autoscaler, so a
            # hard rule would leave a pod Pending instead of doubling up.
            dynamic "pod_anti_affinity" {
              for_each = var.spread_hosts ? [1] : []
              content {
                preferred_during_scheduling_ignored_during_execution {
                  weight = 100

                  pod_affinity_term {
                    topology_key = "kubernetes.io/hostname"

                    label_selector {
                      match_labels = local.spread_hosts_selector
                    }
                  }
                }
              }
            }
          }
        }

        dynamic "toleration" {
          for_each = local.combined_tolerations
          content {
            effect   = toleration.value.effect
            key      = toleration.value.key
            operator = toleration.value.operator
            value    = toleration.value.value
          }
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

        dynamic "volume" {
          for_each = var.network != "prime-testnet" ? toset([1]) : toset([])

          content {
            name = "node-readiness"
            config_map {
              name         = "node-readiness"
              default_mode = "0500"
            }
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

          dynamic "env" {
            for_each = startswith(var.network, "vector") ? toset([1]) : toset([])

            content {
              name  = "NETWORK"
              value = var.network
            }
          }

          dynamic "env" {
            for_each = var.network != "prime-testnet" ? toset([1]) : toset([])

            content {
              name  = "CARDANO_NODE_SOCKET_PATH"
              value = "/ipc/node.socket"
            }
          }

          dynamic "env" {
            for_each = contains(["vector-testnet", "vector-mainnet", "prime-testnet"], var.network) ? toset([]) : toset([1])

            content {
              name  = "CARDANO_NODE_NETWORK_ID"
              value = var.magic
            }
          }

          dynamic "env" {
            for_each = var.rts_opts != null ? toset([1]) : toset([])

            content {
              name  = "CARDANO_RTS_OPTS"
              value = var.rts_opts
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

          dynamic "volume_mount" {
            for_each = var.network != "prime-testnet" ? toset([1]) : toset([])

            content {
              mount_path = "/probes"
              name       = "node-readiness"
            }
          }

          dynamic "volume_mount" {
            for_each = var.is_custom == true ? toset([1]) : toset([])

            content {
              mount_path = "/configuration"
              name       = "network-config"
            }
          }

          dynamic "readiness_probe" {
            for_each = var.readiness_probe != null ? toset([1]) : toset([])

            content {
              failure_threshold     = coalesce(var.readiness_probe.failure_threshold, 10)
              initial_delay_seconds = coalesce(var.readiness_probe.initial_delay_seconds, 10)
              period_seconds        = coalesce(var.readiness_probe.period_seconds, 20)
              success_threshold     = coalesce(var.readiness_probe.success_threshold, 1)
              timeout_seconds       = coalesce(var.readiness_probe.timeout_seconds, 5)

              exec {
                command = local.probe_commands["readiness"]
              }
            }
          }

          dynamic "startup_probe" {
            for_each = var.startup_probe != null ? toset([1]) : toset([])

            content {
              failure_threshold     = coalesce(var.startup_probe.failure_threshold, 10)
              initial_delay_seconds = coalesce(var.startup_probe.initial_delay_seconds, 10)
              period_seconds        = coalesce(var.startup_probe.period_seconds, 20)
              success_threshold     = coalesce(var.startup_probe.success_threshold, 1)
              timeout_seconds       = coalesce(var.startup_probe.timeout_seconds, 5)

              exec {
                command = local.probe_commands["startup"]
              }
            }
          }

          dynamic "liveness_probe" {
            for_each = var.liveness_probe != null ? toset([1]) : toset([])

            content {
              failure_threshold     = coalesce(var.liveness_probe.failure_threshold, 10)
              initial_delay_seconds = coalesce(var.liveness_probe.initial_delay_seconds, 120)
              period_seconds        = coalesce(var.liveness_probe.period_seconds, 20)
              success_threshold     = coalesce(var.liveness_probe.success_threshold, 1)
              timeout_seconds       = coalesce(var.liveness_probe.timeout_seconds, 5)

              exec {
                command = local.probe_commands["liveness"]
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

output "peer_service" {
  value = var.has_local_roots ? {
    cluster_ip                  = "None"
    port                        = 3000
    publish_not_ready_addresses = true
    selector                    = local.peer_service_selector
  } : null
}

output "probe_commands" {
  value = local.probe_commands
}
