locals {
  # Add the extra URL to the list of generated URLs
  dns_names        = ["${var.extension_name}.${var.dns_zone}", "*.${var.extension_name}.${var.dns_zone}"]
  cert_secret_name = "${var.extension_name}-proxy-wildcard-tls"
}

resource "kubernetes_manifest" "certificate_cluster_wildcard_tls" {
  manifest = {
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "Certificate"
    "metadata" = {
      "name"      = local.cert_secret_name
      "namespace" = var.namespace
    }
    "spec" = {
      "dnsNames" = local.dns_names

      "issuerRef" = {
        "kind" = "ClusterIssuer"
        "name" = "letsencrypt-dns01"
      }
      "secretName" = local.cert_secret_name
    }
  }
}

