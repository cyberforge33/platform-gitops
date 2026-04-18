# 🧪 Kind Single-Cluster Platform

This repository provides a simple way to create and manage a local Kubernetes platform using **kind**, a Makefile-driven workflow, and platform components like **Operator Lifecycle Manager (OLM)** and **Argo CD Operator** for GitOps.

It implements a **single-cluster platform model** where:

* A single **Argo CD control plane** runs inside the cluster
* `dev`, `test`, and `prod` are modeled as **namespaces**
* All deployments are managed via **GitOps**

This serves as a lightweight **platform engineering sandbox** for experimenting with:

* Kubernetes Operators
* GitOps workflows
* Environment promotion patterns (dev → test → prod)

---

# 📁 Project Structure

```
.
├── Makefile
├── catalog.yaml
├── operators/
│   └── argo-subscription.yaml
├── kind/
│   └── kind.yaml
└── manifests/
    └── argo/
        ├── argocd.yaml
        ├── project.yaml
        └── application.yaml
```

---

# ⚙️ Prerequisites

Make sure you have the following installed:

* `docker`
* `kind`
* `kubectl`
* `make`
* `curl`
* `argocd` CLI (installed via your Makefile or manually)

---

# 🌍 Environment Configuration

The Makefile uses the following variables:

```
KIND_CLUSTER_NAME ?= platform
KIND_CONFIG_DIR := kind
ARGOCD_SERVER ?= localhost:8000
ARGOCD_NAMESPACE ?= argocd
CSV_NAME ?= argocd-operator.v0.17.0
```

* `KIND_CLUSTER_NAME` → name of your local cluster
* `ARGOCD_SERVER` → Argo CD endpoint (via port-forward)
* `ARGOCD_NAMESPACE` → namespace where Argo CD runs
* `CSV_NAME` → operator version to wait on

You can override variables at runtime.

---

# 🏗️ Architecture

```
        ┌─────────────────────────────┐
        │        kind cluster         │
        │                             │
        │   ┌─────────────────────┐   │
        │   │     Argo CD         │   │
        │   │   (control plane)   │   │
        │   └─────────┬───────────┘   │
        │             │               │
        │   ┌─────────┼─────────┐     │
        │   │         │         │     │
        │  dev       test      prod   │
        │ (ns)      (ns)      (ns)    │
        │                             │
        └─────────────────────────────┘
```

---

# 🚀 Usage

---

## 🏗️ Bootstrap Cluster

Creates the cluster, installs OLM, and installs the Argo CD Operator:

```
make bootstrap-cluster
```

This will:

* Create kind cluster
* Create namespaces (`dev`, `test`, `prod`)
* Install OLM
* Apply operator catalog
* Install Argo CD Operator

---

## 🚀 Bootstrap Argo CD

Waits for the operator and deploys Argo CD + GitOps resources:

```
make bootstrap-argo
```

This will:

* Wait for operator CSV → `Succeeded`
* Deploy Argo CD instance
* Deploy AppProject
* Deploy Application

---

# 🧠 Recommended Workflow

Full platform bootstrap:

```
make platform-up
```

---

# ⚠️ Notes & Tips

### 1. Idempotency

All major commands are safe to re-run:

* cluster creation skips if exists
* namespaces use `|| true`
* operator waits until ready
