variable "namespace" {
  description = "the namespace where the resources will be created"
}

variable "network" {
  description = "the network where the resources will be created"
}

variable "release" {
  description = "the release where the resources will be created"
}

variable "active_salt" {
  description = "the salt to use for the active network"
  default = ""
}

locals {
  selector = length(var.active_salt) > 0 ? {
    "role"    = "node"
    "network" = var.network
    "release" = var.release
    "salt"    = var.active_salt
    } : {
    "role"    = "node"
    "network" = var.network
    "release" = var.release
  }
}

resource "kubernetes_service_v1" "well_known_service" {
  metadata {
    name      = "node-${var.network}-${var.release}"
    namespace = var.namespace
  }

  spec {
    port {
      name     = "n2c"
      protocol = "TCP"
      port     = 3307
    }

    port {
      name     = "n2n"
      protocol = "TCP"
      port     = 3000
    }

    selector = local.selector

    type = "ClusterIP"
  }
}
