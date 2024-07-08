resource "kubernetes_config_map" "node-readiness" {
  metadata {
    namespace = var.namespace
    name      = "node-readiness"
  }

  data = {
    "readiness.sh"   = "${file("${path.module}/readiness.sh")}"
  }
}
