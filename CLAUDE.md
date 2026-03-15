# Homelab GitOps Repository

This is a GitOps repository for managing a k3s homelab cluster using ArgoCD.

## Repository Structure

- `bootstrap/` — One-time setup scripts and manifests (ArgoCD install, initial cluster config)
- `apps/` — ArgoCD Application definitions (what gets deployed and from where)
- `infrastructure/` — Core infrastructure components (cert-manager, ingress, monitoring, etc.)
- `clusters/home/` — Cluster-specific configuration and overrides
- `scripts/` — Helper scripts for common tasks

## Cluster

- **Distribution**: k3s
- **GitOps Tool**: ArgoCD

## Conventions

- All Kubernetes manifests use YAML
- Secrets are never committed to this repo — use sealed-secrets or external-secrets
- ArgoCD Applications live in `apps/` and point to paths within this repo
