resource "kubernetes_service_v1" "proxy_service" {
  metadata {
    name      = local.name
    namespace = var.namespace
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" : "instance"
      "service.beta.kubernetes.io/aws-load-balancer-scheme" : "internet-facing"
      "service.beta.kubernetes.io/aws-load-balancer-type" : "external"
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol" : "HTTP"
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-path" : "/health"
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-port" : var.healthcheck_port != null ? var.healthcheck_port : "traffic-port"
    }
  }

  spec {
    load_balancer_class = "service.k8s.aws/nlb"
    selector            = local.proxy_labels

    port {
      name        = "proxy"
      port        = 9443
      target_port = local.proxy_port
      protocol    = "TCP"
    }

    port {
      name        = "health"
      port        = 80
      target_port = local.prometheus_port
      protocol    = "TCP"
    }

    type = "LoadBalancer"
  }
}
