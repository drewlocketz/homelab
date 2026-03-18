# Synology CSI Driver

## Executive Summary

The Synology CSI driver allows Kubernetes to dynamically provision NFS volumes on a Synology
NAS. Rather than manually creating NFS mounts on each node, the CSI driver handles volume
lifecycle (create, attach, delete) through the standard Kubernetes PersistentVolumeClaim API.
This spec covers NAS-side setup, deploying the CSI driver via ArgoCD, and defining a
StorageClass for NFS-backed volumes. The Synology NAS will provide high-capacity storage for
media files and downloads; application databases and config remain on Longhorn.

**Author:** Drew Locketz
**Date:** 2026-03-16
**Status:** Complete

---

## Human Instructions

These steps must be completed manually in DSM before the CSI driver can be deployed.

**1. Initial DSM setup**
- Power on, navigate to `find.synology.com`, run the setup wizard
- Create your admin account, install all DSM updates

**2. Storage Pool & Volume**
- Open Storage Manager → Storage Pool → Create
- Choose RAID type based on drive count (SHR for mixed sizes, RAID 1 for 2 drives, RAID 5/6 for 4+)
- Create a Volume on the pool, allocate full size

**3. Enable NFS**
- Control Panel → File Services → NFS tab
- Enable NFS service, set minimum NFS version to NFSv4

**4. Create Shared Folders**
- Control Panel → Shared Folder → Create
- Create `media` and `downloads` as separate top-level shares
- Disable Recycle Bin, enable checksum for data integrity

**5. Create a dedicated k8s user**
- Control Panel → User & Group → Create
- Username: `k8s-csi`, strong password, no expiry
- Grant Read/Write on `media` and `downloads` shared folders

**6. Configure NFS permissions on each shared folder**
- Edit shared folder → NFS Permissions → Create
- Hostname/IP: your k3s subnet (e.g. `10.0.4.0/24`)
- Privilege: Read/Write
- Squash: No squash
- Enable async, allow connections from non-privileged ports

**7. Enable Snapshot Replication**
- Install Snapshot Replication from Package Center
- Configure a daily snapshot schedule on `media` and `downloads`
- Set retention policy (e.g. 7 daily, 4 weekly)

**8. Note down before proceeding:**
- NAS IP address
- `k8s-csi` username and password (will become a SealedSecret)
- NFS paths (e.g. `/volume1/media`, `/volume1/downloads`)

---

## Tasks

- [ ] 1. Complete all Human Instructions above
- [x] 2. Create a SealedSecret in `infrastructure/synology-csi/` containing the `k8s-csi` credentials
- [x] 3. Add the Synology CSI Helm chart source to `infrastructure/synology-csi/`
- [x] 4. Define a `StorageClass` for NFS-backed volumes
- [ ] 5. Verify ArgoCD syncs the `synology-csi` Application
- [ ] 6. Verify the CSI driver pods are `Running` in the `synology-csi` namespace
- [ ] 7. Verify dynamic provisioning works by creating a test PVC and confirming it binds

---

## Components

```
  This repo
  ┌──────────────────────────────────────────────┐
  │  infrastructure/synology-csi/                │
  │  ├── Chart.yaml                              │
  │  ├── values.yaml                             │
  │  ├── storageclass.yaml                       │
  │  └── credentials-sealed.yaml (SealedSecret) │
  └──────────────────┬───────────────────────────┘
                     │ ArgoCD syncs
                     ▼
  ┌──────────────────────────────────────────────┐
  │              k3s Cluster                     │
  │                                              │
  │  namespace: synology-csi                     │
  │  ┌────────────────────────────────────┐      │
  │  │   synology-csi controller          │      │
  │  │   synology-csi node daemonset      │      │
  │  └───────────────┬────────────────────┘      │
  │                  │ NFS over network           │
  │  ┌───────────────▼────────────────────┐      │
  │  │   StorageClass: synology-nfs       │      │
  │  │   dynamically provisions PVs       │      │
  │  └────────────────────────────────────┘      │
  └──────────────────────────────────────────────┘
                     │ NFS
                     ▼
  ┌──────────────────────────────────────────────┐
  │              Synology NAS                    │
  │                                              │
  │  /volume1/media      (shared folder)         │
  │  /volume1/downloads  (shared folder)         │
  └──────────────────────────────────────────────┘
```

---

## Success Criteria

- [ ] CSI controller and node pods are `Running` in `synology-csi` namespace
- [ ] `kubectl get storageclass` shows `synology-nfs`
- [ ] A test PVC using `synology-nfs` binds successfully
- [ ] A pod mounting the test PVC can read and write files
- [ ] The provisioned volume is visible on the NAS in DSM

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `docs/specs/sealed-secrets.md` | Sealed Secrets must be deployed before this spec — credentials are stored as a SealedSecret |
| `docs/specs/app-of-apps-structure.md` | ApplicationSet structure — the `infrastructure` ApplicationSet auto-generates the `synology-csi` Application from `infrastructure/synology-csi/` |
| https://github.com/SynologyOpenSource/synology-csi | Official Synology CSI driver |

---

## Design Decisions

### Decision: NFS over iSCSI

**Options considered:**
- iSCSI — block storage, ReadWriteOnce, better for databases
- NFS — file storage, ReadWriteMany, better for shared media access

**Decision:** NFS. Media files and downloads need to be accessible by multiple pods
simultaneously (jellyfin, sonarr, radarr, sabnzbd all mount the same volumes). NFS supports
ReadWriteMany which enables this. iSCSI is ReadWriteOnce and would require one pod to own
each volume exclusively.

**Trade-offs:** NFS has slightly higher latency than iSCSI for small random I/O, but media
workloads are large sequential reads where this difference is negligible.

---

### Decision: No CSI snapshots

**Options considered:**
- Deploy snapshot-controller + VolumeSnapshotClass for Kubernetes-native snapshots
- Rely on Synology's built-in Snapshot Replication for NAS-level snapshots

**Decision:** NAS-level snapshots only. The Synology NAS volumes hold media files and
downloads — stable, write-once data. Application state (databases, config) lives on Longhorn,
not the NAS, so CSI snapshots on Synology-backed volumes would not protect anything critical.
Synology's Snapshot Replication package provides scheduled snapshots and file-level restore
through DSM without adding a snapshot-controller dependency to the cluster.

**Trade-offs:** Snapshots are managed in DSM rather than via kubectl. Acceptable for a homelab.

---

### Decision: Longhorn for app data, Synology for media

**Options considered:**
- All storage on Synology NAS
- All storage on Longhorn
- Split: Longhorn for app data/metadata, Synology for large media files

**Decision:** Split storage. Longhorn provides fast replicated SSD storage for database files
and application config where I/O performance matters. Synology provides high-capacity storage
for movies, TV, and downloads where capacity and multi-pod access matter more than raw speed.

**Trade-offs:** Two storage backends to maintain. The performance and capacity trade-offs
justify the split.
