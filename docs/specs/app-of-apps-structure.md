# ApplicationSet Structure & Repository Layout

## Executive Summary

ArgoCD's ApplicationSet controller allows a single manifest to dynamically generate multiple
ArgoCD Applications using a generator. Rather than manually writing an Application manifest
for every component, two ApplicationSets — one for infrastructure, one for workloads — use
the git directory generator to auto-create a child Application for every directory found
under `infrastructure/` and `workloads/`. Adding a new component is as simple as adding a
new directory; no ApplicationSet manifest changes required.

**Author:** Drew Locketz
**Date:** 2026-03-16
**Status:** Complete

---

## Tasks

### Cleanup (remove old app-of-apps structure)
- [x] 1. Delete `clusters/home/root-app.yaml`
- [x] 2. Delete `clusters/home/infrastructure-app.yaml`
- [x] 3. Delete `clusters/home/workloads-app.yaml`
- [x] 4. Delete `infrastructure/apps/sealed-secrets.yaml` and the `infrastructure/apps/` directory
- [x] 5. Delete the `apps/` directory (empty, never used)

### Scaffold new structure
- [x] 6. Create `clusters/home/infrastructure-appset.yaml` (git directory generator → `infrastructure/*`)
- [x] 7. Create `clusters/home/workloads-appset.yaml` (git directory generator → `workloads/*`)
- [x] 8. Create `infrastructure/sealed-secrets/namespace.yaml` — a stub Namespace manifest to allow the ApplicationSet to be verified end-to-end; other infrastructure components get their placeholder directories when their own specs are implemented
- [x] 9. Create `workloads/` placeholder directories as workload specs are implemented — no stubs added at this stage

### Bootstrap
- [x] 10. Apply both ApplicationSets to the cluster manually (`kubectl apply -f clusters/home/`)
- [x] 11. Verify ArgoCD detects and displays all generated child applications
- [x] 12. Commit and push — verify ArgoCD syncs all apps from Git

---

## Components

### Repository Structure

```
homelab/
├── bootstrap/                        # One-time provisioning (Ansible)
│   └── k3s-ansible/                  # Submodule
├── clusters/
│   └── home/
│       ├── infrastructure-appset.yaml   # Applied manually once — generates infra apps
│       └── workloads-appset.yaml        # Applied manually once — generates workload apps
├── infrastructure/                   # One directory per infra component
│   ├── sealed-secrets/
│   ├── longhorn/
│   ├── synology-csi/
│   ├── traefik/
│   ├── cert-manager/
│   └── monitoring/                   # kube-prometheus-stack + loki
├── workloads/                        # One directory per workload
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
  ┌─────────────────────────┐   ┌─────────────────────────┐
  │  infrastructure-appset  │   │   workloads-appset       │
  │  (ApplicationSet)       │   │   (ApplicationSet)       │
  └───────────┬─────────────┘   └────────────┬────────────┘
              │ generates                     │ generates
              ▼                               ▼
  ┌────────────────────────┐    ┌────────────────────────┐
  │  sealed-secrets  app   │    │  jellyfin app          │
  │  longhorn        app   │    │  jellyseerr app        │
  │  synology-csi    app   │    │  sonarr app            │
  │  traefik         app   │    │  radarr app            │
  │  cert-manager    app   │    │  prowlarr app          │
  │  monitoring      app   │    │  bazarr app            │
  └────────────────────────┘    │  sabnzbd app           │
                                └────────────────────────┘
```

### ApplicationSet Example (infrastructure)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: infrastructure
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: ssh://git@localhost/~/homelab.git
        revision: HEAD
        directories:
          - path: infrastructure/*
  template:
    metadata:
      name: '{{path.basename}}'
      annotations:
        argocd.argoproj.io/sync-wave: '{{metadata.annotations.sync-wave}}'  # see Design Decisions
    spec:
      project: default
      source:
        repoURL: ssh://git@localhost/~/homelab.git
        targetRevision: HEAD
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{path.basename}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
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

- [ ] `kubectl get applicationsets -n argocd` shows `infrastructure` and `workloads`
- [ ] `kubectl get applications -n argocd` shows one Application per component directory
- [ ] All child ArgoCD Applications show `Synced` / `Healthy`
- [ ] sealed-secrets is running before any app that consumes a SealedSecret syncs
- [ ] All workload namespaces exist and pods reach `Running` state
- [ ] Sealed secrets can be decrypted by workloads that use them
- [ ] Jellyfin is accessible via Traefik ingress and can browse media from Synology
- [ ] sabnzbd traffic is routed through gluetun VPN (verify via IP leak test)
- [ ] Any change pushed to `main` is automatically synced by ArgoCD within 3 minutes
- [ ] Adding a new directory under `infrastructure/` or `workloads/` creates a new Application automatically

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `docs/specs/k3s-ansible-bootstrap.md` | Cluster provisioning spec — defines the cluster this runs on |
| `docs/specs/argocd-bootstrap.md` | ArgoCD install spec — defines the ArgoCD instance managing these apps |
| https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/ | Official ArgoCD ApplicationSet documentation |
| https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Git/ | Git directory generator documentation |

---

## Design Decisions

### Decision: ApplicationSet over app-of-apps

**Options considered:**
- App-of-apps: root Application manages child Application manifests stored in Git
- ApplicationSet: generator automatically creates Applications from directory structure

**Decision:** ApplicationSet with git directory generator. Adding a new component requires only
creating a new directory — no Application manifest to write and commit separately. The generator
handles discovery automatically, which scales better and reduces boilerplate.

**Trade-offs:** Slightly less explicit than hand-written Application manifests. Requires the
ApplicationSet controller (bundled with ArgoCD since v2.3).

---

### Decision: Two ApplicationSets (infrastructure + workloads) vs one

**Options considered:**
- Single ApplicationSet covering all directories
- Two ApplicationSets: one for `infrastructure/*`, one for `workloads/*`

**Decision:** Two ApplicationSets. Separating infrastructure from workloads allows independent
sync policies, annotations, and lifecycle management per tier. Infrastructure apps can have
more aggressive retry behavior; workloads can be managed separately without touching infra.

**Trade-offs:** Two manifests to apply at bootstrap instead of one.

---

### Decision: Deployment ordering without sync waves

**Options considered:**
- Sync wave annotations on generated Applications (requires per-app metadata, not supported by git directory generator without a workaround)
- Separate ApplicationSets per wave (e.g., `sealed-secrets-appset.yaml`, `infra-tier1-appset.yaml`)
- Rely on ArgoCD health checks + automated sync retry

**Decision:** Rely on ArgoCD's health checks and automated sync with retry. When a dependent
app (e.g., one consuming a SealedSecret) fails to sync because sealed-secrets isn't ready yet,
ArgoCD will retry on the next sync cycle. Since automated sync is enabled with `selfHeal: true`,
the cluster converges to the correct state within a few sync cycles without explicit wave ordering.

**Trade-offs:** Initial bootstrap takes a few sync cycles to fully converge rather than deploying
in strict order. Acceptable for a homelab where convergence time is not critical. If strict
ordering becomes necessary in the future, the infrastructure ApplicationSet can be split into
wave-based sets.

---

### Decision: Gluetun as sidecar on sabnzbd only

**Options considered:**
- Standalone gluetun pod acting as a gateway for multiple apps
- Gluetun sidecar on each app that needs VPN

**Decision:** Sidecar on sabnzbd only. The Docker gateway pattern (`network_mode: container:gluetun`)
does not translate cleanly to Kubernetes. Only sabnzbd (the downloader) requires VPN — the *arr
apps manage catalogues and talk to sabnzbd's API internally, so they do not need VPN routing.

**Trade-offs:** If additional apps need VPN in future, each will need its own gluetun sidecar.

---

### Decision: Longhorn for metadata, Synology CSI for media

**Options considered:**
- All storage on Longhorn
- All storage on Synology NAS
- Split: Longhorn for app data/metadata, Synology for large media files

**Decision:** Split storage. Longhorn provides fast replicated SSD storage ideal for database
files and application config. Synology NAS provides high-capacity storage for movies, TV, and
downloads where raw throughput matters more than replication speed.

**Trade-offs:** Two storage backends to maintain. The performance and capacity benefits justify
the complexity.
