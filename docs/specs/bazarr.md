# Bazarr Subtitle Management

## Executive Summary

Deploy Bazarr to the k3s cluster to automatically download English subtitles for all
media managed by Sonarr and Radarr. Bazarr integrates with both apps via their APIs
and uses subtitle providers (e.g. OpenSubtitles, Addic7ed) to find and download
matching subtitles. It follows the same workload pattern as Sonarr/Radarr: config on
Longhorn, media on Synology NFS, exposed via Traefik IngressRoute.

**Author:** Drew Locketz
**Date:** 2026-05-03
**Status:** In Progress

---

## Dependencies

| Spec | Why |
|---|---|
| `sonarr-radarr.md` | Bazarr connects to Sonarr and Radarr APIs to know which media needs subtitles |
| `synology-csi.md` | Media PVC requires the Synology NFS CSI driver |
| `longhorn.md` | Config PVC requires Longhorn storage |
| `traefik.md` | Ingress for web access |
| `cert-manager.md` | TLS certificate for the ingress |

---

## Human Instructions

**1. Subtitle provider accounts**
- After deployment, log into the Bazarr web UI and configure at least one subtitle
  provider (e.g. OpenSubtitles.com — requires a free account).

**2. Sonarr/Radarr API keys**
- After deployment, configure the Sonarr and Radarr connections in the Bazarr UI.
  You will need the API keys from each app (found in Settings > General in their UIs).
  Use the cluster-internal service URLs:
  - Sonarr: `http://sonarr.sonarr.svc.cluster.local:8989`
  - Radarr: `http://radarr.radarr.svc.cluster.local:7878`

**3. Language profile**
- Set the default language profile to **English** so all media gets English subtitles.

---

## Tasks

- [x] 1. Create `workloads/bazarr/` directory
- [x] 2. Create `deployment.yaml` — LinuxServer.io Bazarr image, mounting config and media volumes
- [x] 3. Create `service.yaml` — ClusterIP on port 6767
- [x] 4. Create `ingress.yaml` — IngressRoute for `bazarr.home.drewdevlab.com` on `websecure-internal` entrypoint
- [x] 5. Create `pvc-config.yaml` — Longhorn RWO, 5Gi
- [x] 6. Create `pv-media.yaml` and `pvc-media.yaml` — Synology NFS static PV (same shared media volume as Sonarr/Radarr)
- [x] 7. ArgoCD ApplicationSet auto-discovered `workloads/bazarr/` — no manual Application needed
- [x] 8. Verify pod is Running, PVCs bound, and web UI accessible

---

## Components

```
  This repo
  ┌──────────────────────────────────────────┐
  │  workloads/bazarr/                       │
  │  ├── deployment.yaml                     │
  │  ├── service.yaml                        │
  │  ├── ingress.yaml                        │
  │  ├── pvc-config.yaml                     │
  │  ├── pv-media.yaml                       │
  │  └── pvc-media.yaml                      │
  └──────────────┬───────────────────────────┘
                 │ ArgoCD syncs
                 ▼
  ┌──────────────────────────────────────────┐
  │              k3s Cluster                 │
  │                                          │
  │  namespace: bazarr                       │
  │  ┌────────────────────┐                  │
  │  │  Bazarr Deployment │                  │
  │  │  ├── /config (LH)  │                  │
  │  │  └── /storage (NFS)│                  │
  │  └────────┬───────────┘                  │
  │           ▼                              │
  │  Service :6767                           │
  │  IngressRoute                            │
  │  bazarr.home.drewdevlab.com              │
  │                                          │
  │  Connects to:                            │
  │  ├── sonarr.sonarr.svc:8989  (API)      │
  │  └── radarr.radarr.svc:7878  (API)      │
  └──────────────────────────────────────────┘
         │ NFS                │ iSCSI
         ▼                    ▼
  ┌─────────────────┐  ┌─────────────────┐
  │  Synology NAS   │  │    Longhorn     │
  │  (shared media) │  │  (config data)  │
  └─────────────────┘  └─────────────────┘
```

---

## Success Criteria

- [ ] Bazarr pod is `Running` in the `bazarr` namespace
- [ ] Config PVC bound on Longhorn, media PVC bound on Synology NFS
- [ ] Web UI accessible at `https://bazarr.home.drewdevlab.com`
- [ ] TLS certificate is valid
- [ ] Bazarr can connect to Sonarr and Radarr APIs (verified in Bazarr UI)
- [ ] Bazarr can browse media files on the shared NFS volume
- [ ] English subtitles are downloaded for at least one test media item

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `docs/specs/sonarr-radarr.md` | Pattern reference — Bazarr follows the same workload structure |
| `workloads/sonarr/` | Existing workload used as template for manifests |
| `workloads/radarr/` | Same shared media NFS volume that Bazarr needs access to |
| https://docs.linuxserver.io/images/docker-bazarr | LinuxServer.io Bazarr image docs |
| https://www.bazarr.media | Bazarr project documentation |

---

## Design Decisions

### Decision: Shared media volume with Sonarr/Radarr

**Options considered:**
- Separate media PVC provisioned by Synology CSI
- Static PV pointing to the same NFS share used by Sonarr/Radarr

**Decision:** Static PV pointing to the same NFS share. Bazarr needs to read media
files and write subtitle files (.srt/.ass) alongside them. It must see the exact same
directory tree as Sonarr and Radarr.

**Trade-offs:** Another static PV/PVC pair referencing the same Synology share.
Follows the same pattern already used by Sonarr, Radarr, and Jellyfin.

### Decision: No downloads volume

**Options considered:**
- Mount a downloads volume like Sonarr/Radarr
- Only mount media volume

**Decision:** Only mount media. Bazarr does not interact with download clients. It
reads media files and writes subtitle files directly into the media directory.

**Trade-offs:** None.

### Decision: Internal-only ingress

**Options considered:**
- Public ingress (`websecure` entrypoint)
- Internal-only ingress (`websecure-internal` entrypoint)

**Decision:** Internal-only, matching Sonarr/Radarr. Bazarr is an admin tool that
does not need public internet access.

**Trade-offs:** Not accessible outside the home network. Acceptable for a subtitle
management tool.

### Decision: LinuxServer.io image

**Options considered:**
- Official Bazarr image (`ghcr.io/morpheus65535/bazarr`)
- LinuxServer.io image (`lscr.io/linuxserver/bazarr`)

**Decision:** LinuxServer.io, consistent with Sonarr/Radarr/SABnzbd. Provides
PUID/PGID support and follows the same conventions as other *arr workloads in the
cluster.

**Trade-offs:** Third-party image. Same rationale as Sonarr/Radarr decision.
