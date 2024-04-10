locals {
  role = "operator"
  port = 8080
  addr = "0.0.0.0:${local.port}"
}

resource "kubernetes_deployment_v1" "operator" {
  wait_for_rollout = false

  metadata {
    namespace = var.namespace
    name      = local.role
    labels = {
      role = local.role
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        role = local.role
      }
    }

    template {
      metadata {
        labels = {
          role = local.role
        }
      }

      spec {
        container {
          image = "ghcr.io/demeter-run/ext-cardano-node-operator:${var.operator_image_tag}"
          name  = "main"

          env {
            name  = "ADDR"
            value = local.addr
          }

          env {
            name  = "K8S_IN_CLUSTER"
            value = "true"
          }

          env {
            name  = "API_KEY_SALT"
            value = var.api_key_salt
          }

          env {
            name  = "EXTENSION_NAME"
            value = var.extension_name
          }

          env {
            name  = "DNS_ZONE"
            value = var.dns_zone
          }

          resources {
            limits = {
              memory = "512Mi"
            }
            requests = {
              cpu    = "50m"
              memory = "512Mi"
            }
          }

          port {
            name           = "metrics"
            container_port = local.port
            protocol       = "TCP"
          }
        }

        toleration {
          effect   = "NoSchedule"
          key      = "demeter.run/compute-profile"
          operator = "Equal"
          value    = "general-purpose"
        }

        toleration {
          effect   = "NoSchedule"
          key      = "demeter.run/compute-arch"
          operator = "Equal"
          value    = "x86"
        }

        toleration {
          effect   = "NoSchedule"
          key      = "demeter.run/availability-sla"
          operator = "Equal"
          value    = "consistent"
        }
      }
    }
  }
}
