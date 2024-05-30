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

resource "kubernetes_config_map" "node-config" {
  metadata {
    namespace = var.namespace
    name      = "configs-${var.network}-${var.salt}"
  }

  data = {
    "config.json"   = "${file("${path.module}/${var.network}/config.json")}"
    "topology.json" = "${file("${path.module}/${var.network}/topology.json")}"
  }
}

output "cm_name" {
  value = "configs-${var.network}-${var.salt}"
}
