variable "cloud_provider" {
  type    = string
  default = "aws"
}

variable "namespace" {
  type = string
}

variable "dns_zone" {
  type    = string
  default = "demeter.run"
}

variable "extension_name" {
  type    = string
  default = "nodes-m1"
}

// Operator
variable "operator_image_tag" {
  type = string
}

variable "api_key_salt" {
  type = string
}

variable "dcu_per_second" {
  type = map(string)
  default = {
    "mainnet"        = "1"
    "preprod"        = "1"
    "preview"        = "1"
    "sanchonet"      = "1"
    "vector-testnet" = "1"
  }
}

variable "metrics_delay" {
  type    = number
  default = 60
}

variable "operator_resources" {
  type = object({
    limits = object({
      cpu    = string
      memory = string
    })
    requests = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    limits = {
      cpu    = "50m"
      memory = "512Mi"
    }
    requests = {
      cpu    = "50m"
      memory = "512Mi"
    }
  }
}

// Proxy
variable "proxy_green_image_tag" {
  type = string
}

variable "proxy_green_replicas" {
  type    = number
  default = 1
}

variable "proxy_green_healthcheck_port" {
  type        = number
  description = "The port the loadbalancer assigned to the HTTP endpoint of the service. Usually known after the service is created. The default is the target-port."
  default     = null
}

variable "proxy_green_instances_namespace" {
  type = string
}

variable "proxy_blue_image_tag" {
  type = string
}

variable "proxy_blue_replicas" {
  type    = number
  default = 1
}

variable "proxy_blue_healthcheck_port" {
  type        = number
  description = "The port the loadbalancer assigned to the HTTP endpoint of the service. Usually known after the service is created. The default is the target-port."
  default     = null
}

variable "proxy_blue_instances_namespace" {
  type = string
}

variable "proxy_resources" {
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

variable "instances" {
  type = map(object({
    node_image    = string
    image_tag     = string
    network       = string
    salt          = string
    release       = string
    magic         = number
    topology_zone = string
    node_resources = optional(object({
      limits = object({
        cpu    = string
        memory = string
      })
      requests = object({
        cpu    = string
        memory = string
      })
    }))
    storage_size       = optional(string)
    storage_class_name = optional(string, "gp3")
    node_version       = string
    replicas           = number
    restore            = optional(bool)
    compute_arch       = optional(string)
    compute_profile    = optional(string)
    availability_sla   = optional(string)
    is_custom          = optional(bool)
    is_relay           = optional(bool, false)
  }))
}

variable "services" {
  type = map(object({
    network      = string
    release      = string
    node_version = string
    active_salt  = optional(string)
  }))
}
