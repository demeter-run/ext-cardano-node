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

variable "dns_zone" {
  type    = string
  default = "demeter.run"
}

variable "healthcheck_port" {
  type = number
}