# =========================
# Single Cluster GitOps Platform
# =========================

KIND_CLUSTER_NAME ?= platform
KIND_CONFIG_DIR := kind
ARGOCD_SERVER ?= localhost:8000
ARGOCD_NAMESPACE ?= argocd
CSV_NAME ?= argocd-operator.v0.17.0

.PHONY: \
	create delete \
	install-olm setup-olm-catalog \
	argo-subscription wait-argocd-csv \
	deploy-argo deploy-argo-project deploy-argo-application \
	argo-port-forward argo-login argo-admin-password \
	bootstrap-cluster bootstrap-argo


# -------------------------
# Cluster Lifecycle
# -------------------------

create:
	@echo "Creating kind cluster..."
	@kind get clusters | grep -q "^$(KIND_CLUSTER_NAME)$$" && \
		echo "Cluster already exists, skipping..." || \
		kind create cluster \
			--name $(KIND_CLUSTER_NAME) \
			--config $(KIND_CONFIG_DIR)/kind.yaml

delete:
	@kind delete cluster --name $(KIND_CLUSTER_NAME) || true


# -------------------------
# OLM (optional)
# -------------------------

install-olm:
	curl -sL https://github.com/operator-framework/operator-lifecycle-manager/releases/download/v0.42.0/install.sh | bash -s v0.42.0

setup-olm-catalog:
	@echo "Applying OLM catalog..."
	kubectl apply -f catalog.yaml


# -------------------------
# Operator (OLM)
# -------------------------

argo-subscription:
	@echo "Installing Argo CD Operator subscription..."
	kubectl apply -f operators/argo-subscription.yaml


# -------------------------
# Argo CD
# -------------------------
wait-argocd-csv:
	@echo "Waiting for Argo CD Operator CSV to reach Succeeded..."
	@for i in $$(seq 1 60); do \
		PHASE=$$(kubectl get csv -n operators $(CSV_NAME) \
			-o jsonpath='{.status.phase}' 2>/dev/null); \
		echo "Current phase: $$PHASE"; \
		if [ "$$PHASE" = "Succeeded" ]; then \
			echo "✅ CSV is Succeeded"; \
			exit 0; \
		fi; \
		if [ "$$PHASE" = "Failed" ]; then \
			echo "❌ CSV entered Failed state"; \
			exit 1; \
		fi; \
		sleep 10; \
	done; \
	echo "❌ Timeout waiting for CSV"; \
	exit 1

deploy-argo:
	@kubectl get ns $(ARGOCD_NAMESPACE) >/dev/null 2>&1 || kubectl create ns $(ARGOCD_NAMESPACE)
	kubectl apply -f manifests/argo/argocd.yaml

deploy-argo-projects:
	kubectl apply -f manifests/argo/projects/

argo-port-forward:
	@echo "Waiting for Argo CD server to be ready..."
	@kubectl wait --for=condition=available deployment/example-argocd-server -n $(ARGOCD_NAMESPACE) --timeout=300s
	@echo "Port-forwarding Argo CD on http://localhost:8000"
	kubectl port-forward -n $(ARGOCD_NAMESPACE) svc/example-argocd-server 8000:80

argo-login:
	@echo "Logging into Argo CD at $(ARGOCD_SERVER)..."
	@ARGO_ADMIN=$$(kubectl get secret example-argocd-cluster -n $(ARGOCD_NAMESPACE) \
		-o jsonpath="{.data.admin\.password}" | base64 -d); \
	if [ -z "$$ARGO_ADMIN" ]; then \
		echo "❌ Failed to retrieve Argo CD admin password"; \
		exit 1; \
	fi; \
	argocd login $(ARGOCD_SERVER) \
		--username admin \
		--password "$$ARGO_ADMIN" \
		--insecure; \
	echo "✅ Argo CD login complete"

argo-admin-password:
	kubectl get secret example-argocd-cluster -n $(ARGOCD_NAMESPACE) \
		-o jsonpath="{.data.admin\.password}" | base64 -d


# -------------------------
# Bootstrap
# -------------------------

platform-up: bootstrap-cluster bootstrap-argo
	@echo "🚀 Platform fully ready"

bootstrap-cluster:
	@echo "Bootstrapping cluster"
	@$(MAKE) create
	@kubectl get ns olm >/dev/null 2>&1 || $(MAKE) install-olm
	@$(MAKE) setup-olm-catalog
	@$(MAKE) argo-subscription
	@echo "Cluster ready"

bootstrap-argo:      
	@echo "Bootstrapping Argo"	
	@$(MAKE) wait-argocd-csv
	@$(MAKE) deploy-argo
	@$(MAKE) deploy-argo-projects
	@$(MAKE) argo-admin-password
	@$(MAKE) argo-port-forward
	@echo "Argo ready"
