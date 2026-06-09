# 🧪 Kind Single-Cluster Platform (GitOps Sandbox)

This repository provides a local Kubernetes platform using:

* **kind** for cluster provisioning
* **Argo CD** for GitOps reconciliation
* **OLM (Operator Lifecycle Manager v1)** for operator installation
* **Helm + GitOps patterns** for platform services

It implements a **single-cluster platform model** where:

* A single **Argo CD control plane** runs inside the cluster
* `nginx`, `redis`, and `postgresql` are modeled as **managed namespaces**
* All workloads are deployed via **GitOps (no kubectl apply workflows for apps)**
* Infrastructure is split into:

  * Bootstrap layer (cluster + operators)
  * Platform layer (Argo CD + projects)
  * Application layer (Helm/Manifests)

---

# 📁 Project Structure

```
.
├── Makefile
├── catalog.yaml
├── kind/
│   └── kind.yaml
├── manifests/
│   ├── argo/
│   │   ├── argocd.yaml
│   │   ├── project.yaml
│   │   └── application.yaml
│   └── olm/
│       ├── argocd-rbac.yaml
│       └── argocd-extension.yaml
├── argocd/
│   ├── applications/
│   └── projects/
```

---

# ⚙️ Prerequisites

* docker
* kind
* kubectl
* make or just
* curl
* argocd CLI (optional but recommended)

---

# 🌍 Key Architecture Concept

```
                 ┌─────────────────────────────┐
                 │        kind cluster         │
                 │                             │
                 │   ┌─────────────────────┐   │
                 │   │     Argo CD         │   │
                 │   │  (GitOps control)   │   │
                 │   └─────────┬───────────┘   │
                 │             │               │
                 │   ┌─────────┼─────────┐     │
                 │   │         │         │     │
                 │ nginx     redis   postgresql │
                 │ (ns)      (ns)      (ns)     │
                 │                             │
                 └─────────────────────────────┘
```

---

# 🚀 Bootstrap Workflow

## 🏗 Step 1 — Create Cluster + Base Namespaces

```bash
just create
just create-namespaces
```

### Important correction:

Namespaces are created here **because Argo CD does NOT reliably create them unless explicitly configured per Application.**

Each namespace is labeled for Argo management:

```bash
argocd.argoproj.io/managed-by=argocd
```

---

## 🧱 Step 2 — Install OLM v1

```bash
just install-olm
```

---

## ⚙️ Step 3 — Install Argo CD Operator

```bash
just create-argocd-rbac
just install-argocd-operator
just wait-argocd-install
```

---

## 🚀 Step 4 — Deploy Argo CD Instance

```bash
just deploy-argo
```

---

## 📦 Step 5 — Apply GitOps Structure

```bash
just deploy-argo-projects
just deploy-argo-applications
```

This installs:

* AppProjects (security boundaries)
* Applications (workloads)


# 🧠 Design Model (IMPORTANT)

You now have 3 layers:

```
BOOTSTRAP LAYER
→ kind, OLM, Argo CD install

PLATFORM LAYER
→ AppProjects (security boundaries)

APPLICATION LAYER
→ Helm charts (nginx, redis, postgres)
```

---

# 🛠 Key Make Targets

## Full platform bootstrap

```bash
just platform-up
```

---

## Cluster only

```bash
just create
just create-namespaces
```

---

## Argo only

```bash
just bootstrap-argo
```

---

## Access Argo UI

```bash
just argo-port-forward
```
