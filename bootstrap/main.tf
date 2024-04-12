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
  dcu_per_package    = var.dcu_per_package
  resources          = var.operator_resources
}

module "node_v1_proxy" {
  depends_on      = [kubernetes_namespace.namespace]
  source          = "./proxy"
  namespace       = var.namespace
  replicas        = var.proxy_replicas
  extension_name  = var.extension_name
  dns_zone        = var.dns_zone
  proxy_image_tag = var.proxy_image_tag
  resources       = var.proxy_resources
}
