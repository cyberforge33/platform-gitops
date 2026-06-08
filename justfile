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
# ARGO CD
# =========================

argo-install:
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

    kubectl apply -n argocd \
        -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml


argo-wait:
    kubectl wait deployment argocd-server \
        -n argocd \
        --for=condition=available \
        --timeout=300s


argo-add cluster:
    @echo "Adding cluster: {{cluster}}"
    argocd cluster add "kind-{{cluster}}" --name "{{cluster}}"


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
    just argo-install
    just argo-wait
    just argo-add {{cluster}}

    @echo "PROD READY (Argo installed)"


# =========================
# PLATFORM
# =========================

platform-up:
    just bootstrap-dev dev
    just bootstrap-test test
    just bootstrap-prod prod
    @echo "🚀 Platform fully ready"


platform-down:
	just delete-all-clusters
	@echo "💣 Platform fully deleted"