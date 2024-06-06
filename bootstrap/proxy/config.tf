// Numbers here should NOT consider number of proxy replicas, given that we are
// handling long lived connections. Also, they are expressed in MB per second
// and multiplied for simplicity. Example: 1Mb/s => 1 * 1024 * 60 for the 1m
// limiter.
locals {
  config_map_name = var.environment != null ? "${var.environment}-proxy-config" : "proxy-config"

  tiers = [
    {
      "name"            = "0",
      "max_connections" = 1
      "rates" = [
        {
          "interval" = "1m",
          "limit"    = 1024 * 1024 * 60
        }
      ]
    },
    {
      "name"            = "1",
      "max_connections" = 5
      "rates" = [
        {
          "interval" = "1m",
          "limit"    = 1024 * 1024 * 60 * 2
        }
      ]
    },
    {
      "name"            = "2",
      "max_connections" = 25
      "rates" = [
        {
          "interval" = "1m",
          "limit"    = 1024 * 1024 * 60 * 2
        }
      ]
    },
    {
      "name"            = "3",
      "max_connections" = 75
      "rates" = [
        { 
          "interval" = "1m",
          "limit"    = 1024 * 1024 * 60 * 2
        }
      ]
    }
  ]
}

resource "kubernetes_config_map" "proxy" {
  metadata {
    namespace = var.namespace
    name      = local.config_map_name
  }

  data = {
    "tiers.toml" = "${templatefile("${path.module}/proxy-config.toml.tftpl", { tiers = local.tiers })}"
  }
}
