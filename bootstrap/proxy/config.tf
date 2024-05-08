// Numbers here should NOT consider number of proxy replicas, given that we are
// handling long lived connections. Also, they are expressed in MB per second
// and multiplied for simplicity. Example: 1Mb/s => 1 * 1024 * 60 for the 1m
// limiter.
locals {
  tiers = [
    {
      "name" = "0",
      "rates" = [
        {
          "interval" = "1m",
          "limit"    = floor(1 * 1024 * 1024 * 60)
        },
        {
          "interval" = "1d",
          "limit"    = floor(1 * 1024 * 1024 * 60 * 60 * 24)
        }
      ]
    },
    {
      "name" = "1",
      "rates" = [
        {
          "interval" = "1m",
          "limit"    = floor(5 * 1024 * 1024 * 60)
        },
        {
          "interval" = "1d",
          "limit"    = floor(5 * 1024 * 1024 * 60 * 60 * 24)
        }
      ]
    },
    {
      "name" = "2",
      "rates" = [
        {
          "interval" = "1m",
          "limit"    = floor(50 * 1024 * 1024 * 60)
        },
        {
          "interval" = "1d",
          "limit"    = floor(50 * 1024 * 1024 * 60 * 60 * 24)
        }
      ]
    },
    {
      "name" = "3",
      "rates" = [
        {
          "interval" = "1m",
          "limit"    = floor(100 * 1024 * 1024 * 60)
        },
        {
          "interval" = "1d",
          "limit"    = floor(100 * 1024 * 1024 * 60 * 60 * 24)
        }
      ]
    }
  ]
}

resource "kubernetes_config_map" "proxy" {
  metadata {
    namespace = var.namespace
    name      = "proxy-config"
  }

  data = {
    "tiers.toml" = "${templatefile("${path.module}/proxy-config.toml.tftpl", { tiers = local.tiers })}"
  }
}
