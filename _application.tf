resource "kubernetes_config_map_v1" "this" {
  metadata {
    name      = "${local.name}-content"
    namespace = local.namespace

    labels = local.labels
  }

  data = {
    "index.html" = file("${path.module}/index.html")
    "script.js"  = file("${path.module}/script.js")
    "styles.css" = file("${path.module}/styles.css")
    "server.py"  = file("${path.module}/app/server.py")
  }
}

resource "kubernetes_deployment_v1" "this" {
  metadata {
    name      = local.name
    namespace = local.namespace

    labels = local.labels
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name"     = local.name
        "app.kubernetes.io/instance" = "project-demo-bugged"
      }
    }

    strategy {
      type = "RollingUpdate"

      rolling_update {
        max_surge       = "1"
        max_unavailable = "0"
      }
    }

    template {
      metadata {
        annotations = {
          "alten.io/content-sha256" = local.content_hash
        }
        labels = local.labels
      }

      spec {
        automount_service_account_token  = false
        enable_service_links             = false
        termination_grace_period_seconds = 10

        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          run_as_group    = 1000
          fs_group        = 1000

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name              = local.name
          image             = local.runtime_image
          image_pull_policy = "IfNotPresent"
          command           = ["python", "/srv/www/server.py"]

          port {
            name           = "http"
            container_port = 8080
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "25m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "96Mi"
            }
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }

            initial_delay_seconds = 2
            period_seconds        = 5
            timeout_seconds       = 2
            failure_threshold     = 3
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }

            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 2
            failure_threshold     = 3
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            run_as_user                = 1000
            run_as_group               = 1000

            capabilities {
              drop = ["ALL"]
            }

            seccomp_profile {
              type = "RuntimeDefault"
            }
          }

          volume_mount {
            name       = "content"
            mount_path = "/srv/www"
            read_only  = true
          }
        }

        volume {
          name = "content"

          config_map {
            name         = kubernetes_config_map_v1.this.metadata[0].name
            default_mode = "0444"
          }
        }
      }
    }
  }

  wait_for_rollout = true

  depends_on = [
    kubernetes_network_policy_v1.default_deny,
    kubernetes_network_policy_v1.http,
  ]
}

resource "kubernetes_service_v1" "this" {
  metadata {
    name      = local.name
    namespace = local.namespace

    labels = local.labels
  }

  spec {
    selector = {
      "app.kubernetes.io/name"     = local.name
      "app.kubernetes.io/instance" = "project-demo-bugged"
    }

    port {
      name        = "http"
      port        = 8080
      target_port = "http"
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}
