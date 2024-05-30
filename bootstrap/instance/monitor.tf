resource "kubernetes_manifest" "podmonitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      labels = {
        "app.kubernetes.io/component" = "o11y"
        "app.kubernetes.io/part-of"   = "demeter"
      }
      name      = "node-${var.network}-${var.salt}"
      namespace = var.namespace
    }
    spec = {
      selector = {
        matchLabels = {
          role    = "node"
          network = var.network
          salt    = var.salt
        }
      }
      podMetricsEndpoints = [
        {
          port = "metrics",
          path = "/metrics"
        },
        {
          port = "ogmios",
          path = "/metrics"
        }
      ]
    }
  }
}
