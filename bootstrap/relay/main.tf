variable "namespace" {
  description = "the namespace where the resources will be created"
}

resource "kubernetes_service_v1" "node-relay-n2n" {
  metadata {
    name      = "node-relay-n2n"
    namespace = var.namespace
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" : "instance"
      "service.beta.kubernetes.io/aws-load-balancer-scheme" : "internet-facing"
      "service.beta.kubernetes.io/aws-load-balancer-type" : "external"
    }
  }

  spec {
    type = "LoadBalancer"
    load_balancer_class = "service.k8s.aws/nlb"

    selector = {
      "role"    = "node"
      "release" = "stable"
    }

    port {
      name     = "mainnet"
      protocol = "TCP"
      port     = 3000
      target_port = "n2n-mainnet"
    }

    port {
      name     = "preprod"
      protocol = "TCP"
      port     = 3001
      target_port = "n2n-preprod"
    }

    port {
      name     = "preview"
      protocol = "TCP"
      port     = 3002
      target_port = "n2n-preview"
    }




  }
}
