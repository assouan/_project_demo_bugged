import argparse
import ast
import json
import re
import sys
from pathlib import Path


EXPECTED_FILES = {
    ".gitignore",
    ".terraform.lock.hcl",
    "Jenkinsfile",
    "README.md",
    "_application.tf",
    "_network.tf",
    "app/server.py",
    "backend.hcl",
    "index.html",
    "jenkins.ps1",
    "locals.tf",
    "outputs.tf",
    "providers.tf",
    "script.js",
    "styles.css",
    "terraform.tfvars.json",
    "variables.tf",
    "versions.tf",
}
EXPECTED_TAGS = {
    "alten:environment": "development",
    "alten:managed-by": "terraform",
    "alten:project": "project-demo-bugged",
    "alten:team": "project-demo-bugged",
}


def require(condition, message, errors):
    if not condition:
        errors.append(message)


def read_text(root, relative_path, errors):
    path = root / relative_path
    try:
        return path.read_text(encoding="utf-8-sig")
    except (OSError, UnicodeError):
        errors.append(f"unreadable:{relative_path}")
        return ""


def validate(root):
    errors = []

    for relative_path in sorted(EXPECTED_FILES):
        require((root / relative_path).is_file(), f"missing:{relative_path}", errors)

    values_path = root / "terraform.tfvars.json"
    try:
        values = json.loads(values_path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        values = {}
        errors.append("invalid:terraform.tfvars.json")
    require(values == {"tags": EXPECTED_TAGS}, "invalid:tags", errors)

    backend = read_text(root, "backend.hcl", errors)
    for requirement in (
        'secret_suffix    = "project-demo-bugged-journal"',
        'namespace        = "project-demo-bugged-dev"',
        "in_cluster_config = true",
    ):
        require(requirement in backend, "invalid:backend", errors)
    require("token" not in backend.lower(), "forbidden:backend-credential", errors)
    require("password" not in backend.lower(), "forbidden:backend-credential", errors)

    versions = read_text(root, "versions.tf", errors)
    require('required_version = "= 1.15.8"' in versions, "invalid:terraform-version", errors)
    require('backend "kubernetes" {}' in versions, "invalid:backend-type", errors)
    require('version = "~> 3.2.0"' in versions, "invalid:provider-version", errors)

    lock = read_text(root, ".terraform.lock.hcl", errors)
    require('version     = "3.2.1"' in lock, "invalid:provider-lock", errors)
    require(lock.count('h1:') >= 2, "invalid:provider-platform-lock", errors)

    application = read_text(root, "_application.tf", errors)
    for requirement in (
        'automount_service_account_token  = false',
        'read_only_root_filesystem  = true',
        'allow_privilege_escalation = false',
        'drop = ["ALL"]',
        'type = "RuntimeDefault"',
        'type = "ClusterIP"',
    ):
        require(requirement in application, "invalid:workload-security", errors)
    require("prevent_destroy" not in application, "forbidden:prevent-destroy", errors)

    network = read_text(root, "_network.tf", errors)
    require('policy_types = ["Ingress", "Egress"]' in network, "invalid:default-deny", errors)
    require('"kubernetes.io/metadata.name" = local.namespace' in network, "invalid:http-ingress", errors)
    require('port     = "8080"' in network, "invalid:http-port", errors)

    html = read_text(root, "index.html", errors)
    require('<link rel="stylesheet" href="styles.css"' in html, "invalid:stylesheet", errors)
    require('<script src="script.js"></script>' in html, "invalid:script", errors)
    require("localhost" not in html.lower(), "forbidden:localhost", errors)

    server_source = read_text(root, "app/server.py", errors)
    try:
        ast.parse(server_source)
    except SyntaxError:
        errors.append("invalid:app-server-syntax")
    for requirement in (
        'ThreadingHTTPServer(("0.0.0.0", 8080), Handler)',
        '"/healthz"',
        '"X-Content-Type-Options"',
        '"Content-Security-Policy"',
    ):
        require(requirement in server_source, "invalid:app-server-contract", errors)

    pipeline = read_text(root, "Jenkinsfile", errors)
    for requirement in (
        "choice(name: 'ACTION', choices: ['Apply', 'Destroy']",
        "string(name: 'GIT_REF', defaultValue: 'main'",
        "serviceAccountName: project-demo-bugged-dev-ci",
        "alten.io/access-profile: tenant-deployer",
        "terraform init -reconfigure -input=false -lockfile=readonly -backend-config=backend.hcl",
        "X-Alten-Signature",
    ):
        require(requirement in pipeline, "invalid:pipeline-contract", errors)

    for path in root.rglob("*"):
        if not path.is_file() or any(
            generated in path.parts for generated in (".git", ".terraform", ".terraform-data")
        ):
            continue
        relative = path.relative_to(root).as_posix()
        if path.stat().st_size > 1024 * 1024:
            errors.append(f"oversized:{relative}")
        if relative.endswith((".tfstate", ".tfplan")):
            errors.append(f"forbidden:generated:{relative}")

    return sorted(set(errors))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    errors = validate(args.root.resolve())
    if errors:
        print(json.dumps({"status": "invalid", "errors": errors}, separators=(",", ":"), sort_keys=True))
        return 1
    print(json.dumps({"status": "valid", "checks": 18}, separators=(",", ":"), sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
