# =========================
# Single Cluster GitOps Platform (OLM v1)
# =========================
OLM_VERSION := "v1.8.0"
OLM_NAMESPACE := "olm"
ARGOCD_SERVER := "localhost:8000"
ARGOCD_NAMESPACE := "argocd"

# =========================
# CLUSTERS
# =========================

create-cluster cluster:
    @echo "Creating cluster: {{cluster}}"
    kind create cluster --name "{{cluster}}"


list-clusters:
    kind get clusters


use-cluster cluster:
    kubectl config use-context "kind-{{cluster}}"


delete-cluster cluster:
    @echo "Deleting cluster: {{cluster}}"
    kind delete cluster --name "{{cluster}}" || true


delete-all-clusters:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Deleting ALL clusters..."

    for c in $(kind get clusters); do
        echo "Deleting: $c"
        kind delete cluster --name "$c"
    done

# =========================
# OLM v1
# =========================

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


# =========================
# BOOTSTRAP
# =========================

bootstrap-dev cluster:
    @echo "Bootstrapping DEV cluster: {{cluster}}"
    just create-cluster {{cluster}}
    @echo "DEV READY (no Argo)"


bootstrap-test cluster:
    echo "Bootstrapping TEST cluster: {{cluster}}"
    just create-cluster {{cluster}}
    @echo "TEST READY (no Argo)"


bootstrap-prod cluster:
    @echo "Bootstrapping PROD cluster: {{cluster}}"

    just create-cluster {{cluster}}

    @echo "PROD READY (Argo installed)"


# =========================
# PLATFORM
# =========================

bootstrap-all: platform-up olm-up argo-up
    @echo "🚀 Platform ready"


platform-up:
    just bootstrap-dev dev
    just bootstrap-test test
    just bootstrap-prod prod
    @echo "✅ Cluster fully ready"


olm-up:
	just install-olm
	@echo "✅ OLM ready"


argo-up:
	kubectl get ns {{ARGOCD_NAMESPACE}} >/dev/null 2>&1 || kubectl create ns {{ARGOCD_NAMESPACE}}
	just create-argocd-rbac
	just install-argocd-operator
	just wait-argocd-install
	just deploy-argo
	just deploy-argo-projects
	just argo-admin-password
	@echo "✅ Argo ready"


platform-down:
	just delete-all-clusters
	@echo "💣 Platform fully deleted"