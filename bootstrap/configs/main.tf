terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

variable "network" {
  description = "cardano node network"
}

variable "namespace" {
  description = "the namespace where the resources will be created"
}

variable "salt" {
  description = "the salt to use for the network"
}

variable "local_roots" {
  description = "P2P peers that this instance must keep as local roots"
  type = list(object({
    address = string
    port    = number
  }))
  default = []
}

locals {
  baseline_topology = jsondecode(file("${path.module}/${var.network}/topology.json"))

  rendered_topology = merge(local.baseline_topology, {
    localRoots = length(var.local_roots) == 0 ? local.baseline_topology.localRoots : [
      {
        accessPoints = [
          for root in var.local_roots : {
            address = root.address
            port    = root.port
          }
        ]
        advertise = false
        trustable = false
        valency   = length(var.local_roots)
      }
    ]
  })
}

resource "kubernetes_config_map" "node-config" {
  metadata {
    namespace = var.namespace
    name      = "configs-${var.network}-${var.salt}"
  }

  data = {
    "config.json"   = "${file("${path.module}/${var.network}/config.json")}"
    "topology.json" = jsonencode(local.rendered_topology)
  }
}

output "cm_name" {
  value = "configs-${var.network}-${var.salt}"
}

output "topology" {
  value = local.rendered_topology
}
