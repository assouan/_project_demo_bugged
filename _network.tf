resource "kubernetes_network_policy_v1" "default_deny" {
  metadata {
    name      = "${local.name}-default-deny"
    namespace = local.namespace

    labels = local.labels
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name"     = local.name
        "app.kubernetes.io/instance" = "project-demo-bugged"
      }
    }

    policy_types = ["Ingress", "Egress"]
  }
}

resource "kubernetes_network_policy_v1" "http" {
  metadata {
    name      = "${local.name}-http"
    namespace = local.namespace

    labels = local.labels
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name"     = local.name
        "app.kubernetes.io/instance" = "project-demo-bugged"
      }
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = local.namespace
          }
        }
      }

      ports {
        port     = "8080"
        protocol = "TCP"
      }
    }

    policy_types = ["Ingress"]
  }
}

