# Homelab GitOps Repository

## Agent Instructions

Before doing any work in this repository:

1. Read `README.md` for a full overview of the cluster, structure, and workloads
2. Read `docs/spec_driven_development.md` for how specs are written and used
3. Check `docs/specs/` for an existing spec covering your task
4. If no spec exists, create one and wait for approval before implementing
5. Follow the spec exactly; surface anything not covered rather than deciding unilaterally

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
