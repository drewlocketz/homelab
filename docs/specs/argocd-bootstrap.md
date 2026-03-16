# ArgoCD Bootstrap

## Executive Summary

ArgoCD is a declarative GitOps continuous delivery tool for Kubernetes. It runs inside
the cluster, watches a Git repository for changes, and automatically reconciles the
cluster state to match what is declared in that repository. This spec covers installing
ArgoCD on the k3s cluster, pushing this repo to GitHub so ArgoCD can read it, scaffolding
the full app-of-apps repository structure defined in `docs/specs/app-of-apps-structure.md`,
and applying the root Application to hand control of the cluster over to ArgoCD. After
this spec is complete, all future changes to the cluster are made by pushing to Git —
not by running `kubectl apply` manually.

**Author:** Drew Locketz
**Date:** 2026-03-15
**Status:** In Progress

---

## Tasks

### Phase 1 — Configure repo access
- [x] 1. Generate dedicated SSH key pair for ArgoCD (`~/.ssh/argocd_repo_key`)
- [x] 2. Add public key to `~/.ssh/authorized_keys` on this machine
- [x] 3. Register `ssh://drew@10.0.4.37/home/drew/code/homelab` in ArgoCD

### Phase 2 — Install ArgoCD
- [x] 4. Create the `argocd` namespace
- [x] 5. Apply the official ArgoCD install manifest
- [x] 6. Wait for all ArgoCD pods to reach `Running`
- [x] 7. Retrieve the initial admin password
- [x] 8. Verify the ArgoCD UI is accessible via port-forward

### Phase 3 — Scaffold repo structure
- [ ] 9. Create `clusters/home/root-app.yaml`
- [ ] 10. Create `clusters/home/infrastructure-app.yaml`
- [ ] 11. Create `clusters/home/workloads-app.yaml`
- [ ] 12. Create ArgoCD Application manifests for each infrastructure component (with sync waves)
- [ ] 13. Create ArgoCD Application manifests for each workload (with sync waves)
- [ ] 14. Create placeholder manifest directories for each infrastructure component and workload
- [ ] 15. Commit

### Phase 4 — Bootstrap
- [ ] 16. Apply `clusters/home/root-app.yaml` manually — this is the only manual `kubectl apply` after ArgoCD is running
- [ ] 17. Verify root-app, infrastructure-app, and workloads-app appear in ArgoCD
- [ ] 18. Verify all child Applications are detected and show `Synced` / `Healthy`

---

## Components

### Bootstrap Flow

```
  This machine
  ┌────────────────────────────────────────────┐
  │                                            │
  │  1. git push ──────────────────────────┐  │
  │                                        │  │
  │  2. kubectl apply argocd install       │  │
  │                                        │  │
  │  3. kubectl apply root-app.yaml        │  │
  │     (one time only)                    │  │
  └────────────────────────────────────────┼──┘
                                           │
                                     ┌─────▼──────┐
                                     │   GitHub   │
                                     │  (homelab) │
                                     └─────┬──────┘
                                           │ watches (poll / webhook)
                                     ┌─────▼──────┐
                                     │   ArgoCD   │
                                     │ (in k3s)   │
                                     └─────┬──────┘
                                           │ syncs
                              ┌────────────┼────────────┐
                              ▼            ▼             ▼
                         root-app    infra-app     workloads-app
```

### App-of-Apps Hierarchy

```
  clusters/home/root-app.yaml
  (kubectl apply once)
        │
        ▼
  ┌─────────────────────┐
  │      root-app       │  watches: clusters/home/
  └──────────┬──────────┘
             │
      ┌──────┴───────┐
      ▼              ▼
  ┌────────┐    ┌──────────┐
  │ infra  │    │workloads │  watches: infrastructure/apps/
  │  app   │    │   app    │          workloads/apps/
  └────┬───┘    └────┬─────┘
       │              │
       ▼              ▼
  ┌──────────────────────────────────────────────┐
  │  infrastructure/apps/          sync wave     │
  │    sealed-secrets.yaml            1          │
  │    longhorn.yaml                  2          │
  │    synology-csi.yaml              2          │
  │    traefik.yaml                   3          │
  │    cert-manager.yaml              3          │
  │    monitoring.yaml                4          │
  │                                              │
  │  workloads/apps/               sync wave     │
  │    jellyfin.yaml                  5          │
  │    jellyseerr.yaml                5          │
  │    prowlarr.yaml                  5          │
  │    sonarr.yaml                    6          │
  │    radarr.yaml                    6          │
  │    bazarr.yaml                    6          │
  │    sabnzbd.yaml                   6          │
  └──────────────────────────────────────────────┘
```

### Repository Structure After Scaffolding

```
homelab/
├── clusters/
│   └── home/
│       ├── root-app.yaml             # Apply once to bootstrap
│       ├── infrastructure-app.yaml   # App-of-apps: infra tier
│       └── workloads-app.yaml        # App-of-apps: workloads tier
├── infrastructure/
│   ├── apps/                         # ArgoCD Application manifests
│   │   ├── sealed-secrets.yaml
│   │   ├── longhorn.yaml
│   │   ├── synology-csi.yaml
│   │   ├── traefik.yaml
│   │   ├── cert-manager.yaml
│   │   └── monitoring.yaml
│   ├── sealed-secrets/               # k8s manifests (populated later)
│   ├── longhorn/
│   ├── synology-csi/
│   ├── traefik/
│   ├── cert-manager/
│   └── monitoring/
└── workloads/
    ├── apps/                         # ArgoCD Application manifests
    │   ├── jellyfin.yaml
    │   ├── jellyseerr.yaml
    │   ├── prowlarr.yaml
    │   ├── sonarr.yaml
    │   ├── radarr.yaml
    │   ├── bazarr.yaml
    │   └── sabnzbd.yaml
    ├── jellyfin/                     # k8s manifests (populated later)
    ├── jellyseerr/
    ├── prowlarr/
    ├── sonarr/
    ├── radarr/
    ├── bazarr/
    └── sabnzbd/
```

---

## Success Criteria

- [ ] `kubectl get pods -n argocd` shows all ArgoCD pods `Running`
- [ ] ArgoCD UI is accessible (initially via port-forward on port 8080)
- [ ] `kubectl get applications -n argocd` shows `root-app`, `infrastructure-app`, and `workloads-app`
- [ ] All child Application manifests are detected by ArgoCD
- [ ] A test commit pushed to `main` is reflected in ArgoCD within 3 minutes
- [ ] ArgoCD is the only way changes are applied going forward — no manual `kubectl apply` for workloads

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `docs/specs/app-of-apps-structure.md` | Defines the app hierarchy, sync waves, and repo structure this spec implements |
| `docs/specs/k3s-ansible-bootstrap.md` | Cluster this ArgoCD instance runs on |
| https://argo-cd.readthedocs.io/en/stable/operator-manual/installation/ | Official ArgoCD installation docs |
| https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/ | Official app-of-apps docs |

---

## Design Decisions

### Decision: Raw install manifest vs Helm vs Kustomize for ArgoCD itself

**Options considered:**
- Official `install.yaml` from the ArgoCD GitHub releases
- Helm chart (`argo/argo-cd`)
- Kustomize overlay on top of the official manifests

**Decision:** Official `install.yaml` for the initial bootstrap. ArgoCD cannot manage its own installation until it is running — using the raw manifest is the simplest path to get it running. Once running, ArgoCD can manage itself via the app-of-apps pattern if desired in future.

**Trade-offs:** Upgrades require re-applying a newer `install.yaml` rather than a Helm values change. Acceptable for a homelab.

---

### Decision: Local SSH repo vs GitHub

**Options considered:**
- GitHub (public or private)
- Serve repo over SSH from the local machine (`ssh://drew@10.0.4.37/home/drew/code/homelab`)

**Decision:** Local SSH for now. The repo contains the cluster token in `bootstrap/inventory.yml` which is not yet encrypted. Pushing to GitHub before addressing that would expose the secret. A dedicated SSH key pair (`~/.ssh/argocd_repo_key`) was generated and its public key added to `~/.ssh/authorized_keys` on the local machine. ArgoCD uses the private key to pull from `ssh://drew@10.0.4.37/home/drew/code/homelab`.

**Migration path:** Once `bootstrap/inventory.yml` secrets are encrypted with ansible-vault, the repo can be pushed to GitHub and the ArgoCD repo URL updated.

**Trade-offs:** The local machine must be reachable from the cluster at all times. If this machine is down, ArgoCD cannot sync. Acceptable for a homelab.

---

### Decision: ArgoCD UI access method

**Options considered:**
- Port-forward (`kubectl port-forward svc/argocd-server -n argocd 8080:443`)
- Traefik ingress (requires Traefik to already be deployed)
- LoadBalancer service

**Decision:** Port-forward during bootstrap. Traefik is not yet deployed at this stage — it will be deployed by ArgoCD itself as part of the infrastructure tier. Once Traefik is running, a proper ingress for the ArgoCD UI can be added.

**Trade-offs:** UI is not persistently accessible until Traefik is deployed. Acceptable for a homelab bootstrap sequence.
