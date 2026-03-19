# Shared Storage Standardization

## Executive Summary

Standardize the storage approach across all media workloads. Currently each service has its own media PV/PVC pointing at the same Synology NFS share, with inconsistent naming and orphaned PVs from deleted downloads PVCs. This spec consolidates to a single NFS share with subdirectories (`/media` and `/downloads`) so that Sonarr/Radarr can do atomic renames when importing downloads into the media library. Per-service config PVCs on Longhorn remain unchanged.

**Author:** Drew Locketz
**Date:** 2026-03-18
**Status:** Draft

---

## Dependencies

| Spec | Why |
|---|---|
| `longhorn.md` | Config PVCs use Longhorn |
| `synology-csi.md` | Shared data PVs use Synology NFS |

---

## Human Instructions

**1. Create subdirectories on the NFS share**
Ensure the existing NFS share has the following structure:
```
/volume1/k8s-csi-pvc-15af394e-b14a-4a35-9/
├── media/
│   ├── Movies/
│   └── Tv/
└── downloads/
    ├── complete/
    └── incomplete/
```
Move any existing media files into the `media/` subdirectory if they aren't already there.

**2. Clean up orphaned PVs**
After migration is complete, delete Released PVs from previous provisioning:
```bash
kubectl delete pv <released-pv-names>
```

**3. Update Jellyfin library paths**
If Jellyfin's library paths change (e.g. from `/storage/Movies` to `/data/media/Movies`), update them in the Jellyfin UI under Dashboard > Libraries.

**4. Update Sonarr/Radarr root folders**
Update root folder paths in Sonarr (Settings > Media Management) and Radarr to point at `/data/media/Tv` and `/data/media/Movies` respectively. Set download client category paths to `/data/downloads/complete`.

---

## Storage Convention

### Tier 1: Shared Data (Synology NFS)
- **Purpose**: Single NFS share containing both media library and downloads
- **Access**: ReadWriteMany
- **Layout**: Subdirectories `/media` (library) and `/downloads` (staging)
- **Consumers**: All media workloads mount the same share at `/data`
- **Convention**: Static PV named `<namespace>-shared-data`, PVC named `shared-data` in each namespace
- **All PVs point at the same NFS share**: `//10.0.4.42/k8s-csi-pvc-15af394e-b14a-4a35-9`
- **Benefit**: Same filesystem allows atomic renames when Sonarr/Radarr import from `/data/downloads` to `/data/media` (no slow cross-volume copy)

### Tier 2: Per-service Config (Longhorn)
- **Purpose**: Application config, SQLite databases
- **Access**: ReadWriteOnce
- **Convention**: Dynamically provisioned, PVC named `<app>-config` in each namespace
- **No changes needed** — current approach is already correct

---

## Tasks

- [ ] 1. Create subdirectories on NFS share: `media/` and `downloads/` (Human Instruction)
- [ ] 2. Replace `jellyfin-media` PV/PVC with `shared-data` PV/PVC in `workloads/jellyfin/`
- [ ] 3. Replace `sonarr-media` PV/PVC with `shared-data` PV/PVC in `workloads/sonarr/`
- [ ] 4. Replace `radarr-media` PV/PVC with `shared-data` PV/PVC in `workloads/radarr/`
- [ ] 5. Remove `sonarr-downloads` and `radarr-downloads` PV/PVC manifests
- [ ] 6. Remove `jellyfin-media`, `sonarr-media`, `radarr-media` PV manifests
- [ ] 7. Update Jellyfin deployment: mount `shared-data`, change media path to `/data/media`
- [ ] 8. Update Sonarr deployment: mount `shared-data`, set media path `/data/media`, downloads path `/data/downloads`
- [ ] 9. Update Radarr deployment: mount `shared-data`, set media path `/data/media`, downloads path `/data/downloads`
- [ ] 10. Add `shared-data` PV/PVC to SABnzbd spec (downloads path `/data/downloads`)
- [ ] 11. Update Jellyfin library paths in UI (Human Instruction)
- [ ] 12. Update Sonarr/Radarr root folders in UI (Human Instruction)
- [ ] 13. Clean up orphaned/Released PVs (Human Instruction)
- [ ] 14. Verify all services can access media and downloads

> Agents: check off each task as it is completed.

---

## Components

```
  Synology NAS (10.0.4.42)
  ┌──────────────────────────────────────────┐
  │  NFS Share: k8s-csi-pvc-15af394e-...     │
  │  ├── media/                              │
  │  │   ├── Movies/                         │
  │  │   └── Tv/                             │
  │  └── downloads/                          │
  │      ├── complete/                       │
  │      └── incomplete/                     │
  └──────────────┬───────────────────────────┘
                 │ NFS v4.1
                 ▼
  ┌──────────────────────────────────────────────────────┐
  │  k3s Cluster                                         │
  │                                                      │
  │  Static PVs (one per namespace, same NFS share)      │
  │  ┌─────────────────────────────────────────────────┐ │
  │  │  jellyfin-shared-data ──┐                       │ │
  │  │  sonarr-shared-data   ──┼── same NFS share      │ │
  │  │  radarr-shared-data   ──┤                       │ │
  │  │  sabnzbd-shared-data  ──┘                       │ │
  │  └─────────────────────────────────────────────────┘ │
  │                                                      │
  │  Per-namespace PVCs (all named "shared-data")        │
  │  ┌────────────┐ ┌────────┐ ┌────────┐ ┌──────────┐  │
  │  │  jellyfin  │ │ sonarr │ │ radarr │ │ sabnzbd  │  │
  │  │            │ │        │ │        │ │          │  │
  │  │ /data/     │ │ /data/ │ │ /data/ │ │ /data/   │  │
  │  │  media/ ←  │ │  media │ │  media │ │  down-   │  │
  │  │  (read)    │ │  down- │ │  down- │ │  loads   │  │
  │  │            │ │  loads │ │  loads │ │  (write) │  │
  │  │            │ │        │ │        │ │          │  │
  │  │ config     │ │ config │ │ config │ │ config   │  │
  │  │ (longhorn) │ │(longh.)│ │(longh.)│ │(longhorn)│  │
  │  └────────────┘ └────────┘ └────────┘ └──────────┘  │
  └──────────────────────────────────────────────────────┘
```

---

## Success Criteria

- [ ] All data PVs point at the same Synology NFS share
- [ ] PV/PVC naming follows `<namespace>-shared-data` / `shared-data` convention
- [ ] All services mount the share at `/data`
- [ ] Jellyfin can browse and play media from `/data/media`
- [ ] Sonarr/Radarr can access `/data/media` and `/data/downloads`
- [ ] SABnzbd can write to `/data/downloads`
- [ ] Sonarr/Radarr imports from downloads to media are atomic renames (not copies)
- [ ] No orphaned or Released PVs remain
- [ ] Config PVCs remain on Longhorn, unaffected

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `workloads/jellyfin/pvc-media.yaml` | Current Jellyfin media PVC (to be replaced) |
| `workloads/sonarr/pvc-media.yaml` | Current Sonarr media PVC (to be replaced) |
| `workloads/radarr/pvc-media.yaml` | Current Radarr media PVC (to be replaced) |
| `workloads/sonarr/pvc-downloads.yaml` | Current Sonarr downloads PVC (to be removed) |
| `workloads/radarr/pvc-downloads.yaml` | Current Radarr downloads PVC (to be removed) |
| `infrastructure/synology-csi/` | Synology CSI driver providing NFS volumes |

---

## Design Decisions

### Decision: Single NFS share with subdirectories vs separate shares

**Options considered:**
- Option A — Separate NFS shares for media and downloads
- Option B — Single NFS share with `/media` and `/downloads` subdirectories

**Decision:** Chose Option B. A single filesystem means Sonarr/Radarr can do atomic renames (`mv`) when importing completed downloads into the media library. With separate NFS shares, imports require a full copy + delete, which is significantly slower for large files.

**Trade-offs:** Less isolation between media and downloads. A misbehaving download can't fill a separate volume — it shares space with the media library. Acceptable for a homelab where the NAS has ample capacity.

### Decision: Static PV per namespace vs single namespace

**Options considered:**
- Option A — Static PV per namespace, all pointing at the same NFS share
- Option B — Move all media workloads into a single namespace to share PVCs

**Decision:** Chose Option A. Per-namespace PVCs with static PVs maintain namespace isolation while still sharing the underlying storage. Each service keeps its own namespace for RBAC, resource quotas, and ArgoCD application boundaries.

**Trade-offs:** More PV/PVC manifests to maintain (one PV + PVC per namespace). Acceptable given the small number of services and the benefit of namespace isolation.

### Decision: Standardized naming convention

**Options considered:**
- Keep per-app naming (`jellyfin-media`, `sonarr-media`)
- Standardize to `shared-data` across namespaces

**Decision:** Standardize. Using `shared-data` makes it immediately clear that the volume is shared infrastructure, not app-specific. The PV names include the namespace prefix (`<namespace>-shared-data`) to remain globally unique.

**Trade-offs:** Requires updating mount references in all deployments. One-time migration cost.

### Decision: Consistent mount path `/data`

**Options considered:**
- Keep existing mount paths (`/storage`, `/media`, `/downloads`)
- Standardize all mounts to `/data`

**Decision:** Standardize to `/data`. All services mount the shared volume at `/data`, with subdirectories `/data/media` and `/data/downloads`. This provides a consistent, predictable layout across all workloads. Requires a one-time update to Jellyfin library paths and Sonarr/Radarr root folders.

**Trade-offs:** Requires reconfiguring application paths in the UI after deployment. One-time effort.
