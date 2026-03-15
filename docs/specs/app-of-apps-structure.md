# App-of-Apps Pattern & Repository Structure

## Executive Summary

ArgoCD's app-of-apps pattern allows a single "root" ArgoCD Application to manage all
other ArgoCD Applications declaratively. Rather than manually applying each application
to the cluster, the root app points to a directory of ArgoCD Application manifests in
this repo — ArgoCD then reconciles and deploys everything from there. This spec defines
the full repository structure and ArgoCD application hierarchy for this homelab cluster,
covering both infrastructure components and media workloads. The design separates
cluster-critical infrastructure (storage, ingress, secrets) from user-facing workloads
(media stack) to allow independent lifecycle management and deployment ordering via
sync waves.

**Author:** Drew Locketz
**Date:** 2026-03-15
**Status:** Draft

---

## Tasks

- [ ] 1. Scaffold the full directory structure in this repo
- [ ] 2. Create the ArgoCD root Application manifest (`clusters/home/root-app.yaml`)
- [ ] 3. Create the infrastructure app-of-apps Application manifest
- [ ] 4. Create the workloads app-of-apps Application manifest
- [ ] 5. Create placeholder ArgoCD Application manifests for each infrastructure component with correct sync waves
- [ ] 6. Create placeholder ArgoCD Application manifests for each workload
- [ ] 7. Create placeholder manifest directories for each infrastructure component
- [ ] 8. Create placeholder manifest directories for each workload
- [ ] 9. Apply the root app to the cluster manually to bootstrap ArgoCD self-management
- [ ] 10. Verify ArgoCD detects and displays all child applications
- [ ] 11. Commit and push — verify ArgoCD syncs the full hierarchy from Git

---

## Components

### Repository Structure

```
homelab/
├── bootstrap/                        # One-time provisioning (Ansible)
│   └── k3s-ansible/                  # Submodule
├── clusters/
│   └── home/
│       ├── root-app.yaml             # Applied manually once — bootstraps everything
│       ├── infrastructure-app.yaml   # App-of-apps for infrastructure tier
│       └── workloads-app.yaml        # App-of-apps for workloads tier
├── infrastructure/                   # Actual k8s manifests for infra components
│   ├── sealed-secrets/
│   ├── longhorn/
│   ├── synology-csi/
│   ├── traefik/
│   ├── cert-manager/
│   └── monitoring/                   # kube-prometheus-stack + loki
├── workloads/                        # Actual k8s manifests for workloads
│   ├── jellyfin/
│   ├── jellyseerr/
│   ├── sonarr/
│   ├── radarr/
│   ├── prowlarr/
│   ├── bazarr/
│   └── sabnzbd/                      # Includes gluetun sidecar
├── docs/
│   └── specs/
└── scripts/
```

### ArgoCD Application Hierarchy

```
  Git Repo (homelab)
  clusters/home/
        │
        │  kubectl apply (once, manually)
        ▼
  ┌─────────────────┐
  │    root-app     │  ArgoCD Application
  │  (app-of-apps)  │
  └────────┬────────┘
           │ manages
     ┌─────┴──────┐
     ▼            ▼
  ┌──────────┐  ┌──────────┐
  │  infra   │  │workloads │  ArgoCD Applications
  │  app     │  │  app     │  (app-of-apps)
  └────┬─────┘  └────┬─────┘
       │              │
       ▼              ▼
  ┌─────────────────────────────────────────────┐
  │            Child Applications               │
  │                                             │
  │  Infrastructure (sync waves 1-3):           │
  │    wave 1: sealed-secrets                   │
  │    wave 2: longhorn, synology-csi           │
  │    wave 3: traefik, cert-manager            │
  │    wave 4: monitoring (kube-prom, loki)     │
  │                                             │
  │  Workloads (sync wave 5+):                  │
  │    wave 5: jellyfin, jellyseerr             │
  │    wave 5: prowlarr                         │
  │    wave 6: sonarr, radarr, bazarr           │
  │    wave 6: sabnzbd (+gluetun sidecar)       │
  └─────────────────────────────────────────────┘
```

### Storage Layout

```
  ┌─────────────────────────────────────────────────┐
  │                  k3s Cluster                    │
  │                                                 │
  │  Longhorn (fast SSD)    Synology CSI (NAS)      │
  │  ┌─────────────────┐    ┌──────────────────┐    │
  │  │ jellyfin config │    │ /media/movies    │    │
  │  │ jellyfin cache  │    │ /media/tv        │    │
  │  │ sonarr db       │    │ /downloads       │    │
  │  │ radarr db       │    └──────────────────┘    │
  │  │ prowlarr config │             │              │
  │  │ bazarr config   │             │ NFS/iSCSI    │
  │  │ sabnzbd config  │    ┌────────▼─────────┐    │
  │  └─────────────────┘    │  Synology NAS    │    │
  └─────────────────────────┴──────────────────┘    │
  └─────────────────────────────────────────────────┘
```

### sabnzbd Pod (gluetun sidecar)

```
  ┌──────────────────────────────────┐
  │         sabnzbd Pod              │
  │                                  │
  │  ┌────────────┐  ┌────────────┐  │
  │  │  sabnzbd   │  │  gluetun   │  │
  │  │ (container)│  │ (sidecar)  │  │
  │  │            │  │            │  │
  │  │  port 8080 │  │ VPN tunnel │  │
  │  └────────────┘  └────────────┘  │
  │   shared network namespace       │
  │   all traffic routed via VPN     │
  └──────────────────────────────────┘
```

---

## Success Criteria

- [ ] `kubectl get applications -n argocd` shows root-app, infrastructure-app, and workloads-app
- [ ] All child ArgoCD Applications are visible and show `Synced` / `Healthy`
- [ ] Sync waves deploy infrastructure in correct order (sealed-secrets before all others)
- [ ] All workload namespaces exist and pods reach `Running` state
- [ ] Sealed secrets can be decrypted by workloads that use them
- [ ] Jellyfin is accessible via Traefik ingress and can browse media from Synology
- [ ] sabnzbd traffic is routed through gluetun VPN (verify via IP leak test)
- [ ] Any change pushed to `main` in this repo is automatically synced by ArgoCD within 3 minutes

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `docs/specs/k3s-ansible-bootstrap.md` | Cluster provisioning spec — defines the cluster this runs on |
| https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/ | Official ArgoCD app-of-apps documentation |
| https://github.com/k3s-io/k3s-ansible | Ansible submodule used for cluster provisioning |

---

## Design Decisions

### Decision: Two-tier app-of-apps (infrastructure + workloads) vs flat

**Options considered:**
- Flat: one root app managing all child apps directly
- Two-tier: root app manages two group apps (infrastructure, workloads) which each manage their children

**Decision:** Two-tier. Separating infrastructure from workloads allows the infra group to fully sync and stabilize before workloads attempt to start. It also makes it easier to sync or rollback one tier independently.

**Trade-offs:** Slightly more ArgoCD Application objects to manage. Worth it for the deployment ordering guarantees.

---

### Decision: Sync waves for deployment ordering

**Options considered:**
- Manual ordering (apply manifests by hand in sequence)
- ArgoCD sync waves via `argocd.argoproj.io/sync-wave` annotation

**Decision:** Sync waves. Sealed-secrets must be running before any app that consumes a SealedSecret can sync. Longhorn and storage must be available before workloads that claim PVCs. Sync waves encode this ordering declaratively.

**Trade-offs:** Adds an annotation to each Application manifest. No meaningful downside.

---

### Decision: Gluetun as sidecar on sabnzbd only

**Options considered:**
- Standalone gluetun pod acting as a gateway for multiple apps
- Gluetun sidecar on each app that needs VPN

**Decision:** Sidecar on sabnzbd only. The Docker gateway pattern (`network_mode: container:gluetun`) does not translate cleanly to Kubernetes. Only sabnzbd (the downloader) requires VPN — the *arr apps manage catalogues and talk to sabnzbd's API internally, so they do not need VPN routing.

**Trade-offs:** If additional apps need VPN in future, each will need its own gluetun sidecar.

---

### Decision: Longhorn for metadata, Synology CSI for media

**Options considered:**
- All storage on Longhorn
- All storage on Synology NAS
- Split: Longhorn for app data/metadata, Synology for large media files

**Decision:** Split storage. Longhorn provides fast replicated SSD storage ideal for database files and application config. Synology NAS provides high-capacity storage for movies, TV, and downloads where raw throughput matters more than replication speed.

**Trade-offs:** Two storage backends to maintain. The performance and capacity benefits justify the complexity.
