resource "kubernetes_default_service_account_v1" "default" {
  metadata {
    namespace = var.namespace
  }
  automount_service_account_token = false
}

resource "kubernetes_service_account_v1" "operator" {
  metadata {
    name      = "operator"
    namespace = var.namespace
  }
  automount_service_account_token = true
}

resource "kubernetes_service_account_v1" "proxy" {
  metadata {
    name      = "proxy"
    namespace = var.namespace
  }
  automount_service_account_token = true
}

resource "kubernetes_cluster_role_v1" "operator" {
  metadata {
    name = "${var.namespace}-operator"
  }

  rule {
    api_groups = ["demeter.run"]
    resources  = ["cardanonodeports"]
    verbs      = ["get", "list", "watch", "patch"]
  }

  rule {
    api_groups = ["demeter.run"]
    resources  = ["cardanonodeports/status"]
    verbs      = ["patch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "operator" {
  metadata {
    name = "${var.namespace}-operator"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.operator.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.operator.metadata[0].name
    namespace = var.namespace
  }
}

resource "kubernetes_cluster_role_v1" "proxy" {
  metadata {
    name = "${var.namespace}-proxy"
  }

  rule {
    api_groups = ["demeter.run"]
    resources  = ["cardanonodeports"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "proxy" {
  metadata {
    name = "${var.namespace}-proxy"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.proxy.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.proxy.metadata[0].name
    namespace = var.namespace
  }
}

// The proxy Deployments live in their own modules; taking the account name from
// this output orders them after the account and its binding.
output "proxy_service_account_name" {
  value      = kubernetes_service_account_v1.proxy.metadata[0].name
  depends_on = [kubernetes_cluster_role_binding_v1.proxy]
}
