locals {
  namespace = "project-demo-bugged-dev"
  name      = "journal"
  tags      = var.tags
  labels = merge(
    {
      for key, value in local.tags : replace(key, "alten:", "alten.io/") => value
    },
    {
      "app.kubernetes.io/name"       = local.name
      "app.kubernetes.io/instance"   = "project-demo-bugged"
      "app.kubernetes.io/component"  = "frontend"
      "app.kubernetes.io/managed-by" = "terraform"
    },
  )

  runtime_image = "python:3.13.13-alpine3.23@sha256:420cd0bf0f3998275875e02ecd5808168cf0843cbb4d3c536432f729247b2acc"
  content_hash = sha256(join("", [
    file("${path.module}/index.html"),
    file("${path.module}/script.js"),
    file("${path.module}/styles.css"),
    file("${path.module}/app/server.py"),
  ]))
}

