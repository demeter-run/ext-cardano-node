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

variable "extra_local_root_groups" {
  description = "additional local-root groups, each rendered as its own non-advertised group after local_roots"
  type = list(object({
    access_points = list(object({
      address = string
      port    = number
    }))
  }))
  default = []
}

locals {
  baseline_topology_json = file("${path.module}/${var.network}/topology.json")
  baseline_topology      = jsondecode(local.baseline_topology_json)

  local_root_groups = [
    for group in concat(
      length(var.local_roots) == 0 ? [] : [var.local_roots],
      [for group in var.extra_local_root_groups : group.access_points],
      ) : {
      accessPoints = [
        for root in group : {
          address = root.address
          port    = root.port
        }
      ]
      advertise = false
      trustable = false
      valency   = length(group)
    }
  ]

  rendered_topology = merge(local.baseline_topology, {
    localRoots = length(local.local_root_groups) == 0 ? local.baseline_topology.localRoots : local.local_root_groups
  })

  topology_json = length(local.local_root_groups) == 0 ? local.baseline_topology_json : jsonencode(local.rendered_topology)
}

resource "kubernetes_config_map" "node-config" {
  metadata {
    namespace = var.namespace
    name      = "configs-${var.network}-${var.salt}"
  }

  data = {
    "config.json"   = "${file("${path.module}/${var.network}/config.json")}"
    "topology.json" = local.topology_json
  }
}

output "cm_name" {
  value = "configs-${var.network}-${var.salt}"
}

output "topology" {
  value = local.rendered_topology
}

output "topology_json" {
  value = local.topology_json
}
