resource "kubernetes_namespace" "namespace" {
  metadata {
    name = var.namespace
  }
}

module "node_v1_feature" {
  depends_on         = [kubernetes_namespace.namespace]
  source             = "./feature"
  namespace          = var.namespace
  operator_image_tag = var.operator_image_tag
  metrics_delay      = var.metrics_delay
  extension_name     = var.extension_name
  dns_zone           = var.dns_zone
  api_key_salt       = var.api_key_salt
  dcu_per_second     = var.dcu_per_second
  resources          = var.operator_resources
}

// blue (once we have a green, we can update its name to proxy-blue)
module "node_v1_proxy_blue" {
  depends_on          = [kubernetes_namespace.namespace]
  source              = "./proxy"
  namespace           = var.namespace
  replicas            = var.proxy_blue_replicas
  extension_name      = var.extension_name
  dns_zone            = var.dns_zone
  proxy_image_tag     = var.proxy_blue_image_tag
  resources           = var.proxy_resources
  instances_namespace = var.proxy_blue_instances_namespace
  healthcheck_port    = var.proxy_blue_healthcheck_port
  cloud_provider      = var.cloud_provider
  environment         = "blue"
  name                = "proxy-blue"
}

module "node_v1_proxy_green" {
  depends_on          = [kubernetes_namespace.namespace]
  source              = "./proxy"
  namespace           = var.namespace
  replicas            = var.proxy_green_replicas
  extension_name      = var.extension_name
  dns_zone            = var.dns_zone
  proxy_image_tag     = var.proxy_green_image_tag
  resources           = var.proxy_resources
  instances_namespace = var.proxy_green_instances_namespace
  healthcheck_port    = var.proxy_green_healthcheck_port
  cloud_provider      = var.cloud_provider
  environment         = "green"
  name                = "proxy-green"
}


module "instances" {
  depends_on = [kubernetes_namespace.namespace]
  source     = "./instance"
  for_each   = var.instances

  namespace = var.namespace
  replicas  = each.value.replicas
  node_resources = coalesce(each.value.node_resources, {
    limits = {
      "memory" = "2Gi"
      "cpu"    = "8"
    }
    requests = {
      "memory" = "2Gi"
      "cpu"    = "100m"
    }
  })
  storage_class_name = coalesce(each.value.storage_class_name, "gp3")
  storage_size       = coalesce(each.value.storage_size, "50Gi")
  node_image         = each.value.node_image
  node_image_tag     = each.value.image_tag
  release            = each.value.release
  network            = each.value.network
  magic              = each.value.magic
  topology_zone      = each.value.topology_zone
  salt               = each.value.salt
  compute_arch       = coalesce(each.value.compute_arch, "arm64")
  compute_profile    = coalesce(each.value.compute_profile, "mem-intensive")
  availability_sla   = coalesce(each.value.availability_sla, "consistent")
  node_version       = each.value.node_version
  restore            = coalesce(each.value.restore, false)
  is_custom          = coalesce(each.value.is_custom, false)
  is_relay           = coalesce(each.value.is_relay, false)
  tolerations        = coalesce(each.value.tolerations, [])
}

module "custom_configs" {
  depends_on = [kubernetes_namespace.namespace]
  source     = "./configs"
  for_each = {
    for key, instance in var.instances : key => instance
    if instance.is_custom == true
  }

  namespace = var.namespace
  network   = each.value.network
  salt      = each.value.salt
}

module "services" {
  depends_on = [kubernetes_namespace.namespace]
  for_each   = var.services
  source     = "./service"

  namespace    = var.namespace
  network      = each.value.network
  release      = each.value.release
  node_version = each.value.node_version
  active_salt  = each.value.active_salt
}

module "node_relay" {
  depends_on     = [kubernetes_namespace.namespace]
  source         = "./relay"
  namespace      = var.namespace
  cloud_provider = var.cloud_provider
}
