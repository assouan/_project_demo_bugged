output "service" {
  description = "Point d acces prive du journal dans le cluster."
  value = {
    namespace = local.namespace
    name      = kubernetes_service_v1.this.metadata[0].name
    port      = kubernetes_service_v1.this.spec[0].port[0].port
    url       = "http://${kubernetes_service_v1.this.metadata[0].name}.${local.namespace}.svc.cluster.local:8080"
  }
}

