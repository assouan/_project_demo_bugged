pipeline {
  agent {
    kubernetes {
      agentContainer 'jnlp'
      agentInjection true
      defaultContainer 'jnlp'
      showRawYaml false
      yaml '''
apiVersion: v1
kind: Pod
metadata:
  labels:
    alten.io/component: jenkins-agent
    alten.io/access-profile: tenant-deployer
    alten.io/project: project-demo-bugged
spec:
  automountServiceAccountToken: false
  serviceAccountName: project-demo-bugged-dev-ci
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: jnlp
      image: eclipse-temurin:21-jre-jammy@sha256:eebd356ad7358b7094758e5787a6726f332917cfd56feab6457c56dab895cdbf
      imagePullPolicy: IfNotPresent
      workingDir: /home/jenkins/agent
      resources:
        requests:
          cpu: 100m
          memory: 256Mi
        limits:
          cpu: 500m
          memory: 512Mi
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
        seccompProfile:
          type: RuntimeDefault
      volumeMounts:
        - name: runtime
          mountPath: /tmp
    - name: git
      image: alpine/git:2.54.0@sha256:d301ddc314bb6531726d37fbd435b5d736296ad0f77e54246ae78ef74031729d
      imagePullPolicy: IfNotPresent
      command: ["sleep"]
      args: ["99d"]
      resources:
        requests:
          cpu: 25m
          memory: 64Mi
        limits:
          cpu: 200m
          memory: 128Mi
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
        seccompProfile:
          type: RuntimeDefault
      volumeMounts:
        - name: runtime
          mountPath: /tmp
    - name: python
      image: python:3.13.13-alpine3.23@sha256:420cd0bf0f3998275875e02ecd5808168cf0843cbb4d3c536432f729247b2acc
      imagePullPolicy: IfNotPresent
      command: ["sleep"]
      args: ["99d"]
      resources:
        requests:
          cpu: 25m
          memory: 48Mi
        limits:
          cpu: 200m
          memory: 128Mi
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
        seccompProfile:
          type: RuntimeDefault
      volumeMounts:
        - name: runtime
          mountPath: /tmp
    - name: terraform
      image: hashicorp/terraform:1.15.8@sha256:7ae513256f7ce67879e218ae8593d6fbe216ec9e123abe6c94e4e10704857963
      imagePullPolicy: IfNotPresent
      command: ["sleep"]
      args: ["99d"]
      resources:
        requests:
          cpu: 50m
          memory: 96Mi
        limits:
          cpu: 300m
          memory: 256Mi
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
        seccompProfile:
          type: RuntimeDefault
      volumeMounts:
        - name: runtime
          mountPath: /tmp
        - name: kubernetes-api
          mountPath: /var/run/secrets/kubernetes.io/serviceaccount
          readOnly: true
  volumes:
    - name: runtime
      emptyDir:
        sizeLimit: 256Mi
    - name: kubernetes-api
      projected:
        defaultMode: 0440
        sources:
          - serviceAccountToken:
              expirationSeconds: 3600
              path: token
          - configMap:
              name: kube-root-ca.crt
              items:
                - key: ca.crt
                  path: ca.crt
          - downwardAPI:
              items:
                - path: namespace
                  fieldRef:
                    apiVersion: v1
                    fieldPath: metadata.namespace
'''
    }
  }

  parameters {
    choice(name: 'ACTION', choices: ['Apply', 'Destroy'], description: 'Operation Terraform a executer.')
    string(name: 'GIT_REF', defaultValue: 'main', description: 'Branche, tag complet ou SHA a deployer.')
    booleanParam(name: 'CONFIRM_DESTROY', defaultValue: false, description: 'Confirmation obligatoire pour Destroy.')
  }

  options {
    buildDiscarder(logRotator(numToKeepStr: '20'))
    disableConcurrentBuilds(abortPrevious: false)
    skipDefaultCheckout(true)
    timeout(time: 15, unit: 'MINUTES')
  }

  environment {
    TF_IN_AUTOMATION = 'true'
    TF_INPUT = 'false'
  }

  stages {
    stage('Validate request') {
      steps {
        script {
          def requestedRef = params.GIT_REF.trim()
          if (
            requestedRef.length() < 1 ||
            requestedRef.length() > 200 ||
            requestedRef.contains('..') ||
            requestedRef.contains('@{') ||
            requestedRef.endsWith('/') ||
            !(requestedRef ==~ /([0-9a-f]{40}|(refs\/(heads|tags)\/)?[A-Za-z0-9][A-Za-z0-9._\/-]*)/)
          ) {
            error('GIT_REF est invalide.')
          }
          if (params.ACTION == 'Destroy' && !params.CONFIRM_DESTROY) {
            error('CONFIRM_DESTROY doit etre active pour une destruction.')
          }
          env.REQUESTED_GIT_REF = requestedRef
          env.REQUESTED_REMOTE_REF = requestedRef ==~ /[0-9a-f]{40}/
            ? requestedRef
            : (requestedRef.startsWith('refs/') ? requestedRef : "refs/heads/${requestedRef}")
        }
      }
    }

    stage('Checkout') {
      steps {
        deleteDir()
        container('git') {
          script {
            def commitSha = sh(
              returnStdout: true,
              script: '''set -eu
git init -q .
git remote add origin https://github.com/assouan/_project_demo_bugged.git
git -c protocol.version=2 fetch --depth=20 --no-tags origin "$REQUESTED_REMOTE_REF" >&2
git -c advice.detachedHead=false checkout --detach -q FETCH_HEAD
git rev-parse HEAD''',
            ).trim()
            if (!(commitSha ==~ /[0-9a-f]{40}/)) {
              error('Le checkout ne fournit pas de SHA Git valide.')
            }
            env.DEPLOYMENT_GIT_COMMIT = commitSha
          }
        }
      }
    }

    stage('Static validation') {
      steps {
        container('python') {
          sh 'python scripts/validate.py'
        }
      }
    }

    stage('Terraform validation') {
      steps {
        container('terraform') {
          sh '''terraform version
terraform fmt -check -recursive -diff
terraform init -reconfigure -input=false -lockfile=readonly -backend-config=backend.hcl
terraform validate'''
        }
      }
    }

    stage('Plan and execute') {
      steps {
        container('terraform') {
          sh '''mkdir -p "$WORKSPACE/.terraform-data"
plan_file="$WORKSPACE/.terraform-data/change.tfplan"
if [ "$ACTION" = "Destroy" ]; then
  terraform plan -destroy -input=false -lock-timeout=2m -out="$plan_file"
else
  terraform plan -input=false -lock-timeout=2m -out="$plan_file"
fi
terraform apply -input=false -lock-timeout=2m -auto-approve "$plan_file"'''
        }
      }
    }
  }

  post {
    failure {
      script {
        try {
          if (!(env.DEPLOYMENT_GIT_COMMIT ==~ /[0-9a-f]{40}/)) {
            echo 'Diagnostic automatique non declenche : aucun SHA exploitable.'
          } else {
            withCredentials([string(credentialsId: 'ai-helper-trigger-key', variable: 'ALTEN_HELPER_KEY')]) {
              container('python') {
                sh '''python - <<'PY'
import hashlib
import hmac
import json
import os
import secrets
import time
import urllib.request


path = "/api/v1/fixes"
payload = json.dumps(
    {
        "build_number": os.environ.get("BUILD_NUMBER", ""),
        "commit_sha": os.environ["DEPLOYMENT_GIT_COMMIT"],
        "git_ref": os.environ.get("REQUESTED_GIT_REF", ""),
        "job_name": os.environ.get("JOB_NAME", ""),
        "repository": "assouan/_project_demo_bugged",
    },
    separators=(",", ":"),
    sort_keys=True,
).encode("utf-8")
timestamp = str(int(time.time()))
nonce = secrets.token_hex(16)
payload_hash = hashlib.sha256(payload).hexdigest()
canonical = f"POST\\n{path}\\n{timestamp}\\n{nonce}\\n{payload_hash}".encode("utf-8")
signature = hmac.new(os.environ["ALTEN_HELPER_KEY"].encode("utf-8"), canonical, hashlib.sha256).hexdigest()
request = urllib.request.Request(
    f"http://90.55.221.116:55123{path}",
    data=payload,
    method="POST",
    headers={
        "Content-Type": "application/json",
        "X-Alten-Nonce": nonce,
        "X-Alten-Signature": signature,
        "X-Alten-Timestamp": timestamp,
    },
)
with urllib.request.urlopen(request, timeout=10) as response:
    result = json.loads(response.read(4096).decode("utf-8"))
fix_id = result.get("id", "")
if not isinstance(fix_id, str) or len(fix_id) != 16 or any(character not in "0123456789abcdef" for character in fix_id):
    raise SystemExit("invalid helper response")
print(f"Diagnostic disponible : https://helper.alten:9003/fix?id={fix_id}")
PY'''
              }
            }
          }
        } catch (Exception ignored) {
          echo 'Le diagnostic automatique est temporairement indisponible.'
        }
      }
    }

    cleanup {
      deleteDir()
    }
  }
}
