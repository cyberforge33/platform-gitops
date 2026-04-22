# =========================
# Single Cluster GitOps Platform (OLM v1)
# =========================

KIND_CLUSTER_NAME := "platform"
KIND_CONFIG_DIR := "kind"
OLM_VERSION := "v1.8.0"
ARGOCD_SERVER := "localhost:8000"
ARGOCD_NAMESPACE := "argocd"


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
	kubectl create ns argocd --dry-run=client -o yaml | kubectl apply -f -
	kubectl create ns olm --dry-run=client -o yaml | kubectl apply -f -


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
	kubectl create ns argocd || true
	kubectl apply -f manifests/olm/argocd-rbac.yaml

install-argocd-operator:
	@echo "Installing Argo CD via ClusterExtension..."
	kubectl apply -f manifests/olm/argocd-extension.yaml

wait-argocd-install:
	@echo "Waiting for ClusterExtension to stabilize..."
	for i in $(seq 1 60); do \
		STATUS=$$(kubectl get clusterextension argocd -o jsonpath='{.status.conditions[?(@.type=="Installed")].status}' 2>/dev/null); \
		echo "Installed status: $$STATUS"; \
		if [ "$$STATUS" = "True" ]; then \
			echo "✅ Argo CD installed"; \
			exit 0; \
		fi; \
		sleep 10; \
	done; \
	echo "❌ Timeout waiting for Argo CD install"; \
	exit 1


# -------------------------
# Argo CD
# -------------------------

deploy-argo:
	@echo "Deploying Argo CD instance..."
	kubectl get ns {{ARGOCD_NAMESPACE}} >/dev/null 2>&1 || kubectl create ns {{ARGOCD_NAMESPACE}}
	kubectl apply -f manifests/argo/argocd.yaml


deploy-argo-projects:
	@echo "Waiting for Argo CD server deployment..."
	until kubectl get deployment example-argocd-server -n {{ARGOCD_NAMESPACE}} >/dev/null 2>&1; do \
		echo "⏳ waiting..."; \
		sleep 5; \
	done

	@echo "Waiting for Argo CD server to be ready..."
	kubectl wait --for=condition=available deployment/example-argocd-server \
		-n {{ARGOCD_NAMESPACE}} --timeout=300s

	@echo "Deploying Argo CD projects..."
	kubectl apply -f manifests/argo/projects/


# -------------------------
# Argo CD Access
# -------------------------

argo-port-forward:
	@echo "Port-forwarding Argo CD on http://localhost:8000"
	kubectl port-forward -n {{ARGOCD_NAMESPACE}} svc/example-argocd-server 8000:80


argo-login:
	@echo "Logging into Argo CD at {{ARGOCD_SERVER}}..."
	ARGO_ADMIN=$$(kubectl get secret example-argocd-cluster -n {{ARGOCD_NAMESPACE}} \
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
	kubectl get secret example-argocd-cluster -n {{ARGOCD_NAMESPACE}} \
		-o jsonpath="{.data.admin\.password}" | base64 -d


# -------------------------
# Bootstrap
# -------------------------

platform-up: bootstrap-cluster bootstrap-argo
	@echo "🚀 Platform fully ready"


bootstrap-cluster:
	just create
	just create-namespaces
	just install-olm
	just create-argocd-rbac
	just install-argocd-operator
	just wait-argocd-install
	@echo "Cluster ready"


bootstrap-argo:
	@echo "Bootstrapping Argo CD..."
	just deploy-argo
	just deploy-argo-projects
	just argo-admin-password
	just argo-port-forward
	@echo "✅ Argo ready"