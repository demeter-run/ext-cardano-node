locals {
  name = var.name
  role = "proxy"

  prometheus_port = 9187
  prometheus_addr = "0.0.0.0:${local.prometheus_port}"
  proxy_port      = 8080
  proxy_addr      = "0.0.0.0:${local.proxy_port}"
  proxy_labels    = var.environment != null ? { role = "${local.role}-${var.environment}" } : { role = local.role }
}

variable "name" {
  type    = string
  default = "proxy"
}

// blue - green
variable "environment" {
  default = null
}

variable "namespace" {
  type = string
}

variable "replicas" {
  type    = number
  default = 1
}

variable "proxy_image_tag" {
  type = string
}

variable "instances_namespace" {
  type = string
}

variable "resources" {
  type = object({
    limits = object({
      cpu               = string
      memory            = string
      ephemeral_storage = string
    })
    requests = object({
      cpu               = string
      memory            = string
      ephemeral_storage = string
    })
  })
  default = {
    limits : {
      cpu : "50m",
      memory : "250Mi"
      ephemeral_storage : "4Gi"
    }
    requests : {
      cpu : "50m",
      memory : "250Mi"
      ephemeral_storage : "4Gi"
    }
  }
}

variable "node_port" {
  type    = number
  default = 3307
}

variable "node_dns" {
  type    = string
  default = "ftr-nodes-v2.svc.cluster.local"
}

variable "extension_name" {
  type = string
}

variable "extra_annotations" {
  description = "Extra annotations to add to the proxy services"
  type        = map(string)
  default     = {}
}

variable "dns_names" {
  description = "List of DNS names for the certificate"
  type        = list(string)
  default     = null
}

variable "dns_zone" {
  type    = string
  default = "demeter.run"
}

variable "healthcheck_port" {
  type = number
}

variable "cloud_provider" {
  type = string
}

variable "tolerations" {
  description = "List of tolerations for the node"
  type = list(object({
    effect   = string
    key      = string
    operator = string
    value    = optional(string)
  }))
  default = [
    {
      effect   = "NoSchedule"
      key      = "demeter.run/compute-profile"
      operator = "Equal"
      value    = "general-purpose"
    },
    {
      effect   = "NoSchedule"
      key      = "demeter.run/compute-arch"
      operator = "Equal"
      value    = "x86"
    },
    {
      effect   = "NoSchedule"
      key      = "demeter.run/availability-sla"
      operator = "Equal"
      value    = "consistent"
    }
  ]
}
