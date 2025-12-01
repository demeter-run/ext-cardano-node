variable "cloud_provider" {
  type    = string
  default = "aws"
}

variable "namespace" {
  type = string
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

// Proxy green
variable "proxy_green_extra_annotations" {
  type    = map(string)
  default = {}
}

variable "proxy_green_healthcheck_port" {
  type        = number
  description = "The port the loadbalancer assigned to the HTTP endpoint of the service. Usually known after the service is created. The default is the target-port."
  default     = null
}

variable "proxy_green_image_tag" {
  type = string
}

variable "proxy_green_instances_namespace" {
  type = string
}

variable "proxy_green_replicas" {
  type    = number
  default = 1
}

// Proxy blue
variable "proxy_blue_extra_annotations" {
  type    = map(string)
  default = {}
}

variable "proxy_blue_healthcheck_port" {
  type        = number
  description = "The port the loadbalancer assigned to the HTTP endpoint of the service. Usually known after the service is created. The default is the target-port."
  default     = null
}

variable "proxy_blue_image_tag" {
  type = string
}

variable "proxy_blue_instances_namespace" {
  type = string
}

variable "proxy_blue_replicas" {
  type    = number
  default = 1
}

// Proxy
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

variable "proxy_green_tolerations" {
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

variable "proxy_blue_tolerations" {
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

variable "instances" {
  type = map(object({
    node_image = string
    image_tag  = string
    network    = string
    salt       = string
    release    = string
    magic      = number
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
    rts_opts           = optional(string)
    readiness_probe = optional(object({
      failure_threshold     = optional(number)
      initial_delay_seconds = optional(number)
      period_seconds        = optional(number)
      success_threshold     = optional(number)
      timeout_seconds       = optional(number)
    }))
    liveness_probe = optional(object({
      failure_threshold     = optional(number)
      initial_delay_seconds = optional(number)
      period_seconds        = optional(number)
      success_threshold     = optional(number)
      timeout_seconds       = optional(number)
    }))
    startup_probe = optional(object({
      failure_threshold     = optional(number)
      initial_delay_seconds = optional(number)
      period_seconds        = optional(number)
      success_threshold     = optional(number)
      timeout_seconds       = optional(number)
    }))
    tolerations = optional(list(object({
      effect   = string
      key      = string
      operator = string
      value    = string
    })), [])
    node_affinity = optional(object({
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
    }))
  }))
}

variable "services" {
  type = map(object({
    name         = optional(string)
    network      = string
    release      = string
    node_version = string
    active_salt  = optional(string)
  }))
}
