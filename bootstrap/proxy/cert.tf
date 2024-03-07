locals {
  by_network = [
    for network in var.networks :
    "*.${network}.${var.extension_name}.${var.dns_zone}"
  ]

  # Add the extra URL to the list of generated URLs
  dns_names        = concat(local.by_network, ["*.${var.extension_name}.${var.dns_zone}"])
  cert_secret_name = "${var.extension_name}-wildcard-tls"
}

resource "kubernetes_manifest" "certificate_cluster_wildcard_tls" {
  manifest = {
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "Certificate"
    "metadata" = {
      "name"      = "${var.extension_name}-wildcard-tls"
      "namespace" = var.namespace
    }
    "spec" = {
      "dnsNames" = local.dns_names

      "issuerRef" = {
        "kind" = "ClusterIssuer"
        "name" = "letsencrypt"
      }
      "secretName" = local.cert_secret_name
    }
  }
}
