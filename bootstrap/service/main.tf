variable "namespace" {
  description = "the namespace where the resources will be created"
}

variable "name" {
  description = "name of the service"
  default     = null
}

variable "network" {
  description = "the network where the resources will be created"
}

variable "release" {
  description = "the release where the resources will be created"
}

variable "active_salt" {
  description = "the salt to use for the active network"
  default     = ""
}

variable "node_version" {
  description = "the version of the node"
}

variable "headless" {
  description = "When true, the Service is headless and publishes Ready pods only, so its DNS and SRV records list just the nodes that can serve."
  type        = bool
  default     = false
}

variable "pdb_max_unavailable" {
  description = "When set, a PodDisruptionBudget named after the Service caps voluntary disruptions of its pods at this many."
  type        = number
  default     = null

  validation {
    condition     = var.pdb_max_unavailable == null || try(var.pdb_max_unavailable >= 0 && floor(var.pdb_max_unavailable) == var.pdb_max_unavailable, false)
    error_message = "pdb_max_unavailable must be a non-negative whole number of pods."
  }
}

locals {
  selector = length(var.active_salt) > 0 ? {
    "role"         = "node"
    "network"      = var.network
    "node-version" = var.node_version
    "salt"         = var.active_salt
    } : {
    "role"         = "node"
    "network"      = var.network
    "node-version" = var.node_version
  }

  name = coalesce(var.name, "node-${var.network}-${var.release}")
}

resource "kubernetes_service_v1" "well_known_service" {
  metadata {
    name      = local.name
    namespace = var.namespace
  }

  spec {
    cluster_ip = var.headless ? "None" : null

    # Unlike the nodes-<salt> peer Services, a headless pool must drop a pod
    # from DNS while it is not Ready, or clients keep dialling a dead node.
    publish_not_ready_addresses = var.headless ? false : null

    port {
      name     = "n2c"
      protocol = "TCP"
      port     = 3307
    }

    port {
      name     = "n2n"
      protocol = "TCP"
      port     = 3000
    }

    selector = local.selector

    type = "ClusterIP"
  }
}

resource "kubernetes_pod_disruption_budget_v1" "pool" {
  count = var.pdb_max_unavailable != null ? 1 : 0

  metadata {
    name      = local.name
    namespace = var.namespace
  }

  spec {
    max_unavailable = tostring(var.pdb_max_unavailable)

    selector {
      match_labels = local.selector
    }
  }
}
