# Prowlarr Indexer Manager

## Executive Summary

Deploy Prowlarr as the centralized indexer manager for the *arr stack. Prowlarr manages indexer configurations in one place and syncs them to Sonarr and Radarr, eliminating the need to configure indexers separately in each app. Config is stored on Longhorn and the web UI is exposed via Traefik ingress with TLS.

**Author:** Drew Locketz
**Date:** 2026-03-18
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
- Create a DNS record for `prowlarr.home.drewdevlab.com` pointing to the Traefik LoadBalancer IP

**2. Configure Sonarr and Radarr integration**
- In Prowlarr UI: Settings > Apps
- Add Sonarr: Prowlarr Server = `http://prowlarr.prowlarr.svc.cluster.local:9696`, Sonarr Server = `http://sonarr.sonarr.svc.cluster.local:8989`, API Key from Sonarr
- Add Radarr: Prowlarr Server = `http://prowlarr.prowlarr.svc.cluster.local:9696`, Radarr Server = `http://radarr.radarr.svc.cluster.local:7878`, API Key from Radarr

**3. Add indexers**
- In Prowlarr UI: Indexers > Add Indexer
- Configure desired indexers; they will automatically sync to Sonarr and Radarr

---

## Tasks

- [x] 1. Create `workloads/prowlarr/` directory
- [x] 2. Create `pvc-config.yaml` — Longhorn PVC (ReadWriteOnce, 5Gi)
- [x] 3. Create `deployment.yaml` — linuxserver/prowlarr container with config volume, Recreate strategy
- [x] 4. Create `service.yaml` — ClusterIP on port 9696
- [x] 5. Create `ingress.yaml` — Traefik IngressRoute for `prowlarr.home.drewdevlab.com` with wildcard TLS
- [ ] 6. Verify ArgoCD syncs the Prowlarr application
- [ ] 7. Verify Prowlarr is accessible via the ingress URL

> Agents: check off each task as it is completed.

---

## Components

```
  This repo
  ┌──────────────────────────────────────────────────┐
  │  workloads/prowlarr/                             │
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
  │  namespace: prowlarr                             │
  │  ┌────────────────────────────────────────┐      │
  │  │   Prowlarr Deployment                 │      │
  │  │   └── /config  ← Longhorn PVC         │      │
  │  └──────────────┬─────────────────────────┘      │
  │                 │                                 │
  │  ┌──────────────▼─────────────────────────┐      │
  │  │   Service :9696                        │      │
  │  │   IngressRoute (prowlarr.home...)      │      │
  │  └────────────────────────────────────────┘      │
  │                 │ syncs indexers to               │
  │        ┌───────┴───────┐                         │
  │        ▼               ▼                         │
  │  ┌──────────┐   ┌──────────┐                     │
  │  │  Sonarr  │   │  Radarr  │                     │
  │  └──────────┘   └──────────┘                     │
  └──────────────────────────────────────────────────┘
```

---

## Success Criteria

- [ ] Prowlarr pod is `Running` in the `prowlarr` namespace
- [ ] Config PVC is bound and backed by Longhorn
- [ ] Prowlarr web UI is accessible via `https://prowlarr.home.drewdevlab.com`
- [ ] TLS certificate is valid (wildcard cert from cert-manager)
- [ ] Sonarr and Radarr can be added as apps in Prowlarr settings
- [ ] Indexers added in Prowlarr sync to Sonarr and Radarr

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `workloads/jellyfin/` | Reference for plain-manifest workload pattern |
| `workloads/sonarr/deployment.yaml` | Reference for linuxserver.io container conventions (PUID/PGID/TZ) |
| `workloads/radarr/deployment.yaml` | Reference for *arr app deployment pattern |
| `docs/specs/jellyfin.md` | Reference spec for a workload deployment |
| https://wiki.servarr.com/prowlarr | Official Prowlarr documentation |
| https://docs.linuxserver.io/images/docker-prowlarr/ | LinuxServer Prowlarr container docs |

---

## Design Decisions

### Decision: Config-only storage

**Options considered:**
- Mount media and downloads volumes (like Sonarr/Radarr)
- Config volume only

**Decision:** Config only. Prowlarr is an indexer manager — it doesn't interact with media files or downloads directly. It only needs persistent storage for its SQLite database and configuration.

**Trade-offs:** None. Adding extra volumes would be unnecessary.

### Decision: Recreate deployment strategy

**Options considered:**
- RollingUpdate (default)
- Recreate

**Decision:** Recreate. Same as Jellyfin — Prowlarr uses SQLite in the config PVC (RWO), so RollingUpdate would deadlock on the volume multi-attach.

**Trade-offs:** Brief downtime during rollouts, acceptable for a homelab.

### Decision: Plain manifests over Helm chart

**Options considered:**
- Use a Helm chart (e.g. bjw-s common chart)
- Write plain Kubernetes manifests

**Decision:** Plain manifests, consistent with Jellyfin, Sonarr, and Radarr. Prowlarr's deployment is simple (single container, one volume, a service, an ingress). No templating needed.

**Trade-offs:** No templating for values. Acceptable for a single-instance deployment.
