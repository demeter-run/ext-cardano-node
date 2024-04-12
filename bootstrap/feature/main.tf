variable "namespace" {
  type = string
}

variable "api_key_salt" {
  type = string
}

variable "extension_name" {
  type = string
}

variable "dns_zone" {
  type = string
}

variable "operator_image_tag" {
  type = string
}

variable "metrics_delay" {
  description = "The inverval for polling metrics data (in seconds)"
  default     = "30"
}

variable "dcu_per_package" {
  type = map(string)
  default = {
    "mainnet"        = "10"
    "preprod"        = "5"
    "preview"        = "5"
    "sanchonet"      = "5"
    "vector-testnet" = "5"
  }
}

variable "resources" {
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
