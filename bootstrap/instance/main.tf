terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

variable "replicas" {
  description = "the number of replicas for the node STS"
  default     = 1
}

variable "node_resources" {
  type = object({
    requests = map(string)
    limits   = map(string)
  })

  default = {
    limits = {
      memory = "2Gi"
    }
    requests = {
      cpu    = "100m"
      memory = "2Gi"
    }
  }
}

variable "storage_size" {
  default = "50Gi"
}

variable "node_image" {
  description = "the OCI image of the cardano-node"
}

variable "node_image_tag" {
  description = "the tag of the cardano-node OCI image"
}

variable "release" {
  description = "the version of the cardano-node being deployed in a k8s-friendly syntax"
}

variable "network" {
  description = "cardano node network name (mainnet, preprod, preview)"
}

variable "magic" {
  description = "cardano node network magic (int)"
}

variable "namespace" {
  description = "the namespace where the resources will be created"
}

variable "topology_zone" {}

variable "salt" {}

variable "sync_status" {
  default = "pending"
}

variable "compute_arch" {
  default = "arm64"
}

variable "compute_profile" {
  default = "mem-intensive"
}

variable "availability_sla" {
  default = "consistent"
}

variable "node_version" {
  type = string
}

variable "restore" {
  default = false
}

variable "is_custom" {
  default = false
}
