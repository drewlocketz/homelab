# Jellyseerr Media Request Manager

## Executive Summary

Deploy Jellyseerr as the media request management tool for the homelab. Jellyseerr provides a clean UI where users can browse and request movies and TV shows, which are then automatically fulfilled via Radarr and Sonarr. It integrates with Jellyfin for authentication and media library awareness. This completes the *arr stack by adding the user-facing request layer.

**Author:** Drew Locketz
**Date:** 2026-03-20
**Status:** Draft

---

## Dependencies

This spec cannot be implemented until the following specs are complete:

| Spec | Why |
|---|---|
| `longhorn.md` | Config PVC requires Longhorn storage |
| `traefik.md` | Ingress for web access |
| `cert-manager.md` | TLS certificate for the ingress |
| `metallb.md` | LoadBalancer IP for Traefik |

---

## Human Instructions

These steps must be completed after deployment.

**1. DNS record**
- Create a DNS record for `jellyseerr.home.drewdevlab.com` pointing to the Traefik LoadBalancer IP

**2. Initial setup wizard**
- Open `https://jellyseerr.home.drewdevlab.com`
- Select Jellyfin as the media server
- Connect to Jellyfin: `http://jellyfin.jellyfin.svc.cluster.local:8096`
- Sign in with Jellyfin admin credentials and sync libraries

**3. Configure Sonarr integration**
- In Jellyseerr: Settings > Services > Sonarr
- Server: `http://sonarr.sonarr.svc.cluster.local:8989`
- API Key: from Sonarr Settings > General
- Configure quality profile and root folder

**4. Configure Radarr integration**
- In Jellyseerr: Settings > Services > Radarr
- Server: `http://radarr.radarr.svc.cluster.local:7878`
- API Key: from Radarr Settings > General
- Configure quality profile and root folder

---

## Tasks

- [x] 1. Create `workloads/jellyseerr/` directory
- [x] 2. Create `pvc-config.yaml` — Longhorn PVC (ReadWriteOnce, 5Gi)
- [x] 3. Create `deployment.yaml` — fallenbagel/jellyseerr container with config volume, Recreate strategy
- [x] 4. Create `service.yaml` — ClusterIP on port 5055
- [x] 5. Create `ingress.yaml` — Traefik IngressRoute for `jellyseerr.home.drewdevlab.com` with wildcard TLS
- [ ] 6. Verify ArgoCD syncs the Jellyseerr application
- [ ] 7. Verify Jellyseerr is accessible via the ingress URL

> Agents: check off each task as it is completed.

---

## Components

```
  This repo
  ┌──────────────────────────────────────────────────┐
  │  workloads/jellyseerr/                           │
  │  ├── deployment.yaml                             │
  │  ├── service.yaml                                │
  │  ├── ingress.yaml                                │
  │  └── pvc-config.yaml       (longhorn)            │
  └──────────────────┬───────────────────────────────┘
                     │ ArgoCD syncs
                     ▼
  ┌──────────────────────────────────────────────────┐
  │              k3s Cluster                         │
  │                                                  │
  │  namespace: jellyseerr                           │
  │  ┌────────────────────────────────────────┐      │
  │  │   Jellyseerr Deployment               │      │
  │  │   └── /app/config  ← Longhorn PVC     │      │
  │  └──────────────┬─────────────────────────┘      │
  │                 │                                 │
  │  ┌──────────────▼─────────────────────────┐      │
  │  │   Service :5055                        │      │
  │  │   IngressRoute (jellyseerr.home...)    │      │
  │  └────────────────────────────────────────┘      │
  │                 │ requests fulfilled by           │
  │        ┌───────┼───────┐                         │
  │        ▼       │       ▼                         │
  │  ┌──────────┐  │ ┌──────────┐                    │
  │  │  Sonarr  │  │ │  Radarr  │                    │
  │  └──────────┘  │ └──────────┘                    │
  │                ▼                                  │
  │         ┌──────────┐                              │
  │         │ Jellyfin │                              │
  │         └──────────┘                              │
  └──────────────────────────────────────────────────┘
```

---

## Success Criteria

- [ ] Jellyseerr pod is `Running` in the `jellyseerr` namespace
- [ ] Config PVC is bound and backed by Longhorn
- [ ] Jellyseerr web UI is accessible via `https://jellyseerr.home.drewdevlab.com`
- [ ] TLS certificate is valid (wildcard cert from cert-manager)
- [ ] Setup wizard loads and can connect to Jellyfin
- [ ] Sonarr and Radarr can be added as services in Jellyseerr settings

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `workloads/prowlarr/` | Reference for config-only workload pattern |
| `workloads/sonarr/` | Sonarr service that Jellyseerr connects to |
| `workloads/radarr/` | Radarr service that Jellyseerr connects to |
| `workloads/jellyfin/` | Jellyfin service that Jellyseerr authenticates against |
| `docs/specs/prowlarr.md` | Reference spec for a similar workload deployment |
| https://github.com/Fallenbagel/jellyseerr | Official Jellyseerr repository |

---

## Design Decisions

### Decision: Config-only storage

**Options considered:**
- Mount media volumes
- Config volume only

**Decision:** Config only. Jellyseerr is a request management UI — it doesn't interact with media files directly. It only needs persistent storage for its SQLite database and configuration.

**Trade-offs:** None. Adding extra volumes would be unnecessary.

### Decision: Recreate deployment strategy

**Options considered:**
- RollingUpdate (default)
- Recreate

**Decision:** Recreate. Jellyseerr uses SQLite in the config PVC (RWO), so RollingUpdate would deadlock on the volume multi-attach.

**Trade-offs:** Brief downtime during rollouts, acceptable for a homelab.

### Decision: No PUID/PGID environment variables

**Options considered:**
- Set PUID/PGID like other *arr apps
- Omit PUID/PGID

**Decision:** Omit. Jellyseerr uses the `fallenbagel/jellyseerr` image, not a LinuxServer.io image. It does not support PUID/PGID environment variables. The container runs as its own default user.

**Trade-offs:** None — this is the correct approach for this image.

### Decision: Plain manifests over Helm chart

**Options considered:**
- Use a Helm chart
- Write plain Kubernetes manifests

**Decision:** Plain manifests, consistent with all other workloads. Jellyseerr's deployment is simple (single container, one volume, a service, an ingress).

**Trade-offs:** No templating for values. Acceptable for a single-instance deployment.
