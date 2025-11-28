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

variable "storage_class_name" {
  default = "gp3"
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

variable "node_affinity" {
  type = object({
    required_during_scheduling_ignored_during_execution = optional(
      object({
        node_selector_term = optional(
          list(object({
            match_expressions = optional(
              list(object({
                key      = string
                operator = string
                values   = list(string)
              })), []
            )
          })), []
        )
      }), {}
    )
    preferred_during_scheduling_ignored_during_execution = optional(
      list(object({
        weight = number
        preference = object({
          match_expressions = optional(
            list(object({
              key      = string
              operator = string
              values   = list(string)
            })), []
          )
          match_fields = optional(
            list(object({
              key      = string
              operator = string
              values   = list(string)
            })), []
          )
        })
      })), []
    )
  })
  default = {}
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

variable "is_relay" {
  default = false
}

variable "rts_opts" {
  type    = string
  default = null
}

variable "readiness_probe" {
  description = "When enabled, configures a readiness probe for the node."
  type = object({
    failure_threshold     = optional(number)
    initial_delay_seconds = optional(number)
    period_seconds        = optional(number)
    success_threshold     = optional(number)
    timeout_seconds       = optional(number)
  })
  default = null
}

variable "tolerations" {
  description = "List of tolerations for the node"
  type = list(object({
    effect   = string
    key      = string
    operator = string
    value    = string
  }))
  default = []
}
