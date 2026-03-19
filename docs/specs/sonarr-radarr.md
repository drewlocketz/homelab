# Sonarr & Radarr Media Management

## Executive Summary

Deploy Sonarr (TV series management) and Radarr (movie management) to the k3s cluster.
Both apps follow the same deployment pattern as Jellyfin: config on Longhorn, media and
downloads on Synology NFS. They are exposed via Traefik IngressRoutes with TLS. Unlike
Jellyfin, neither requires GPU passthrough or privileged access.

**Author:** Drew Locketz
**Date:** 2026-03-18
**Status:** In Progress

---

## Dependencies

| Spec | Why |
|---|---|
| `synology-csi.md` | Media and downloads PVCs require the `synology-nfs` StorageClass |
| `longhorn.md` | Config PVCs require Longhorn storage |
| `traefik.md` | Ingress for web access |
| `cert-manager.md` | TLS certificate for the ingress |
| `jellyfin.md` | Validates the workload pattern these deployments follow |

---

## Human Instructions

**1. DNS records**
- `sonarr.home.drewdevlab.com` and `radarr.home.drewdevlab.com` should resolve via the
  existing `*.home.drewdevlab.com` wildcard record pointing to Traefik's MetalLB IP.
  No new DNS configuration is needed.

---

## Tasks

### Sonarr
- [ ] 1. Create `workloads/sonarr/` directory with deployment manifests
- [ ] 2. Define a PVC for config storage using Longhorn (RWO, 5Gi)
- [ ] 3. Define a PVC for media storage using `synology-nfs` (RWX, 10Ti)
- [ ] 4. Define a PVC for downloads storage using `synology-nfs` (RWX, 1Ti)
- [ ] 5. Create a Deployment with the Sonarr container, mounting all three PVCs
- [ ] 6. Create a Service (ClusterIP) on port 8989
- [ ] 7. Create an IngressRoute for `sonarr.home.drewdevlab.com`

### Radarr
- [ ] 8. Create `workloads/radarr/` directory with deployment manifests
- [ ] 9. Define a PVC for config storage using Longhorn (RWO, 5Gi)
- [ ] 10. Define a PVC for media storage using `synology-nfs` (RWX, 10Ti)
- [ ] 11. Define a PVC for downloads storage using `synology-nfs` (RWX, 1Ti)
- [ ] 12. Create a Deployment with the Radarr container, mounting all three PVCs
- [ ] 13. Create a Service (ClusterIP) on port 7878
- [ ] 14. Create an IngressRoute for `radarr.home.drewdevlab.com`

### Verification
- [ ] 15. Verify ArgoCD syncs both applications
- [ ] 16. Verify both pods are `Running` in their respective namespaces
- [ ] 17. Verify web UIs are accessible via ingress URLs

---

## Components

```
  This repo
  ┌──────────────────────────────────────────────────────┐
  │  workloads/sonarr/              workloads/radarr/    │
  │  ├── deployment.yaml            ├── deployment.yaml  │
  │  ├── service.yaml               ├── service.yaml     │
  │  ├── ingress.yaml               ├── ingress.yaml     │
  │  ├── pvc-config.yaml            ├── pvc-config.yaml  │
  │  ├── pvc-media.yaml             ├── pvc-media.yaml   │
  │  └── pvc-downloads.yaml         └── pvc-downloads.yaml│
  └──────────────┬──────────────────────┬────────────────┘
                 │ ArgoCD syncs         │
                 ▼                      ▼
  ┌──────────────────────────────────────────────────────┐
  │              k3s Cluster                             │
  │                                                      │
  │  namespace: sonarr              namespace: radarr    │
  │  ┌────────────────────┐  ┌────────────────────┐     │
  │  │  Sonarr Deployment │  │  Radarr Deployment │     │
  │  │  ├── /config (LH)  │  │  ├── /config (LH)  │     │
  │  │  ├── /media  (NFS) │  │  ├── /media  (NFS) │     │
  │  │  └── /downloads    │  │  └── /downloads    │     │
  │  │      (NFS)         │  │      (NFS)         │     │
  │  └────────┬───────────┘  └────────┬───────────┘     │
  │           ▼                       ▼                  │
  │  Service :8989            Service :7878              │
  │  IngressRoute             IngressRoute               │
  │  sonarr.home.             radarr.home.               │
  │  drewdevlab.com           drewdevlab.com             │
  └──────────────────────────────────────────────────────┘
         │ NFS                    │ iSCSI/replicated
         ▼                       ▼
  ┌─────────────────┐    ┌─────────────────┐
  │  Synology NAS   │    │    Longhorn     │
  │  /volume1/media │    │  (config data)  │
  │  /volume1/      │    └─────────────────┘
  │   downloads     │
  └─────────────────┘
```

---

## Success Criteria

- [ ] Sonarr pod is `Running` in the `sonarr` namespace
- [ ] Radarr pod is `Running` in the `radarr` namespace
- [ ] All PVCs are bound (config on Longhorn, media and downloads on Synology NFS)
- [ ] Sonarr web UI is accessible via `https://sonarr.home.drewdevlab.com`
- [ ] Radarr web UI is accessible via `https://radarr.home.drewdevlab.com`
- [ ] TLS certificates are valid (issued by cert-manager)
- [ ] Both apps can browse files on the media and downloads volumes

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `docs/specs/jellyfin.md` | Pattern reference — Sonarr/Radarr follow the same workload structure |
| `docs/specs/synology-csi.md` | Provides the `synology-nfs` StorageClass for media and downloads |
| `docs/specs/longhorn.md` | Provides Longhorn storage for config |
| `docs/specs/traefik.md` | Traefik ingress controller for routing |
| `workloads/jellyfin/` | Existing workload used as template |
| https://docs.linuxserver.io/images/docker-sonarr | LinuxServer.io Sonarr image docs |
| https://docs.linuxserver.io/images/docker-radarr | LinuxServer.io Radarr image docs |

---

## Design Decisions

### Decision: Separate NFS PVCs per namespace

**Options considered:**
- Shared PVCs across namespaces (requires PV/PVC in each namespace pointing to same share)
- Separate PVCs per namespace, each dynamically provisioned

**Decision:** Separate PVCs per namespace. Each namespace gets its own PVC for media and
downloads. The Synology CSI driver provisions them from the same underlying NAS shares, so
there is no storage duplication — just separate Kubernetes PVC objects.

**Trade-offs:** More PVC objects to manage. Simpler than cross-namespace volume sharing
and follows Kubernetes namespace isolation conventions.

### Decision: LinuxServer.io images

**Options considered:**
- Official Sonarr/Radarr images
- LinuxServer.io (lscr.io) images

**Decision:** LinuxServer.io images. They provide consistent PUID/PGID environment variable
support for file permission management, regular automated builds, and a uniform configuration
pattern across all *arr apps. Widely used in the homelab community.

**Trade-offs:** Third-party images rather than upstream. LinuxServer.io has a strong track
record and publishes source Dockerfiles.

### Decision: No privileged access or GPU passthrough

**Options considered:**
- Run with elevated privileges for potential hardware access
- Standard unprivileged containers

**Decision:** Standard unprivileged. Sonarr and Radarr are metadata managers and API-driven
apps — they do not transcode media or need GPU access. No `securityContext` escalation needed.

**Trade-offs:** None. This is strictly simpler and more secure.

### Decision: Downloads volume for future download client integration

**Options considered:**
- Only mount media volume (add downloads later when a download client is deployed)
- Mount both media and downloads volumes now

**Decision:** Mount both now. When a download client (e.g. SABnzbd, qBittorrent) is added,
Sonarr/Radarr need access to the downloads directory to import completed files. Pre-mounting
avoids redeploying these workloads later.

**Trade-offs:** An extra PVC per app that won't be actively used until a download client
is deployed. Minimal overhead.

### Decision: Plain manifests over Helm chart

**Options considered:**
- Helm charts (k8s-at-home or similar community charts)
- Plain Kubernetes manifests

**Decision:** Plain manifests, consistent with the Jellyfin workload pattern. These are
simple single-container deployments where Helm adds indirection without value.

**Trade-offs:** No templating. Acceptable for single-instance homelab deployments.
