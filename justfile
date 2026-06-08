# =========================
# Single Cluster GitOps Platform (OLM v1)
# =========================

KIND_CLUSTER_NAME := "platform"
KIND_CONFIG_DIR := "kind"
OLM_VERSION := "v1.8.0"
OLM_NAMESPACE := "olm"
ARGOCD_SERVER := "localhost:8000"
ARGOCD_NAMESPACE := "argocd"
NGINX_NAMESPACE := "nginx"
REDIS_NAMESPACE := "redis"
POSTGRESQL_NAMESPACE := "postgresql"

# -------------------------
# Install/Update K8s Tools
# -------------------------
update-k9s:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Downloading the latest K9s Debian package..."
    wget https://github.com/derailed/k9s/releases/latest/download/k9s_linux_amd64.deb
    
    echo "Installing K9s..."
    sudo apt install ./k9s_linux_amd64.deb
    
    echo "Cleaning up installer package..."
    rm k9s_linux_amd64.deb
    
    echo "Successfully updated!"
    k9s version

# -------------------------
# Install/Update Argo CD CLI
# -------------------------
update-argo-cli:
    #!/usr/bin/env bash
    set -euo pipefail

    TMP_FILE=$(mktemp)

    if command -v argocd >/dev/null 2>&1; then
        echo "Updating Argo CD CLI..."
        argocd version --client || true
    else
        echo "Installing Argo CD CLI..."
    fi

    curl -fsSL \
      -o "$$TMP_FILE" \
      https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64

    chmod +x "$$TMP_FILE"

    sudo install -m 755 "$$TMP_FILE" /usr/local/bin/argocd

    rm -f "$$TMP_FILE"

    argocd version --client


# -------------------------
# Cluster Lifecycle
# -------------------------

create:
	@echo "Creating kind cluster..."
	kind get clusters | grep -q "^{{KIND_CLUSTER_NAME}}$" && \
		echo "Cluster already exists, skipping..." || \
		kind create cluster \
			--name {{KIND_CLUSTER_NAME}} \
			--config {{KIND_CONFIG_DIR}}/kind.yaml

delete:
	kind delete cluster --name {{KIND_CLUSTER_NAME}} || true


create-namespaces:
	@echo "Creating required namespaces..."	
	kubectl create ns {{OLM_NAMESPACE}} --dry-run=client -o yaml | kubectl apply -f -
	kubectl create ns {{ARGOCD_NAMESPACE}} --dry-run=client -o yaml | kubectl apply -f -

	kubectl create ns {{NGINX_NAMESPACE}} --dry-run=client -o yaml | kubectl apply -f -
	kubectl label namespace {{NGINX_NAMESPACE}} argocd.argoproj.io/managed-by=argocd

	kubectl create ns {{REDIS_NAMESPACE}} --dry-run=client -o yaml | kubectl apply -f -
	kubectl label namespace {{REDIS_NAMESPACE}} argocd.argoproj.io/managed-by=argocd

	kubectl create ns {{POSTGRESQL_NAMESPACE}} --dry-run=client -o yaml | kubectl apply -f -
	kubectl label namespace {{POSTGRESQL_NAMESPACE}} argocd.argoproj.io/managed-by=argocd


# -------------------------
# MetalLB
# -------------------------
install-metallb:
	kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
	kubectl -n metallb-system rollout status deployment/controller
	kubectl -n metallb-system rollout status daemonset/speaker
	kubectl apply -f manifests/metallb/


# -------------------------
# Ingress Controller
# -------------------------
install-ingress:
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
	kubectl -n ingress-nginx rollout status deployment ingress-nginx-controller


# -------------------------
# Metric Server
# -------------------------
install-metric-server:
	kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
	kubectl -n kube-system patch deployment metrics-server \
	  --type='json' \
	  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
	kubectl -n kube-system rollout status deployment metrics-server


# -------------------------
# OLM v1 (operator-controller)
# -------------------------

install-olm:
	@echo "Installing OLM v1 (operator-controller {{OLM_VERSION}})..."
	curl -L -s https://github.com/operator-framework/operator-controller/releases/download/{{OLM_VERSION}}/install.sh | bash -s


# -------------------------
# Operator Install (OLM v1)
# -------------------------

create-argocd-rbac:
	@echo "Creating Argo CD installer RBAC..."
	kubectl apply -f manifests/olm/argocd-rbac.yaml

install-argocd-operator:
	@echo "Installing Argo CD via ClusterExtension..."
	kubectl apply -f manifests/olm/argocd-extension.yaml

wait-argocd-install:
	@echo "Waiting for ClusterExtension ArgoCD to be Installed..."
	kubectl wait clusterextension argocd \
		--for=jsonpath='{.status.conditions[?(@.type=="Installed")].status}'=True \
		--timeout=600s

# -------------------------
# Argo CD
# -------------------------

deploy-argo:
	@echo "Deploying Argo CD instance..."
	kubectl get ns {{ARGOCD_NAMESPACE}} >/dev/null 2>&1 || kubectl create ns {{ARGOCD_NAMESPACE}}
	kubectl apply -f manifests/argo/argocd.yaml

deploy-argo-projects:
	@echo "Waiting for Argo CD server deployment..."
	until kubectl get deployment argocd-server -n {{ARGOCD_NAMESPACE}} >/dev/null 2>&1; do \
		echo "⏳ waiting..."; \
		sleep 5; \
	done

	@echo "Waiting for Argo CD server to be ready..."
	kubectl wait --for=condition=available deployment/argocd-server \
		-n {{ARGOCD_NAMESPACE}} --timeout=300s

	@echo "Deploying Argo CD projects..."
	kubectl apply -f argocd/projects/

deploy-argo-applications:
	@echo "Deploying Argo CD applications..."
	kubectl apply -f argocd/applications/



# -------------------------
# Argo CD Access
# -------------------------

argo-port-forward:
	@echo "Port-forwarding Argo CD on http://localhost:8000"
	kubectl port-forward -n {{ARGOCD_NAMESPACE}} svc/argocd-server 8000:80


argo-login:
	@echo "Logging into Argo CD at {{ARGOCD_SERVER}}..."
	ARGO_ADMIN=$$(kubectl get secret argocd-cluster -n {{ARGOCD_NAMESPACE}} \
		-o jsonpath="{.data.admin\.password}" | base64 -d); \
	if [ -z "$$ARGO_ADMIN" ]; then \
		echo "❌ Failed to retrieve Argo CD admin password"; \
		exit 1; \
	fi; \
	argocd login {{ARGOCD_SERVER}} \
		--username admin \
		--password "$$ARGO_ADMIN" \
		--insecure; \
	echo "✅ Argo CD login complete"


argo-admin-password:
	@kubectl get secret argocd-cluster -n {{ARGOCD_NAMESPACE}} \
		-o jsonpath="{.data.admin\.password}" | base64 -d; \
	echo " 🔥"


# -------------------------
# Bootstrap
# -------------------------

platform-up: bootstrap-tools bootstrap-exam-prep bootstrap-cluster bootstrap-argo
	@echo "🚀 Platform fully ready"

bootstrap-tools:
	just update-k9s
	just update-argo-cli
	@echo "Tools all up-to-date"

bootstrap-exam-prep:
	just create
	just create-namespaces
	just install-metric-server
	@echo "Exam prep ready"

bootstrap-cluster:
	just install-olm
	just create-argocd-rbac
	just install-argocd-operator
	just wait-argocd-install
	@echo "Cluster ready"

bootstrap-argo:
	@echo "Bootstrapping Argo CD..."
	just deploy-argo
	just deploy-argo-projects
	just deploy-argo-applications
	just argo-admin-password
	just argo-port-forward
	@echo "✅ Argo ready"