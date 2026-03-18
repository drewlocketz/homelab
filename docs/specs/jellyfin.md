# Jellyfin Media Server

## Executive Summary

Deploy Jellyfin as the primary media server on the k3s cluster. Media files are stored on the
Synology NAS via the Synology CSI driver (NFS), while Jellyfin's config and metadata database
are stored on Longhorn for fast I/O. Jellyfin is exposed via Traefik ingress with TLS. Intel
QuickSync hardware transcoding is enabled by passing through the GPU device on each node.

**Author:** Drew Locketz
**Date:** 2026-03-17
**Status:** Complete

---

## Dependencies

This spec cannot be implemented until the following specs are complete:

| Spec | Why |
|---|---|
| `synology-csi.md` | Media PVC requires the `synology-nfs` StorageClass |
| `longhorn.md` | Config PVC requires Longhorn storage |
| `traefik.md` | Ingress for web access |
| `cert-manager.md` | TLS certificate for the ingress |
| `metallb.md` | LoadBalancer IP for Traefik |
| `sealed-secrets.md` | Already complete — needed if any secrets are required |

---

## Human Instructions

These steps must be completed before or during deployment.

**1. DNS record**
- Create a DNS record (e.g. `jellyfin.yourdomain.com`) pointing to the Traefik LoadBalancer IP

**2. Verify Intel QuickSync availability**
- SSH into a node and confirm `/dev/dri/renderD128` exists
- `ls -la /dev/dri/` should show `card0` and `renderD128`
- If the device is not present, check that the `i915` kernel module is loaded (`lsmod | grep i915`)

---

## Tasks

- [ ] 1. Verify `/dev/dri/renderD128` exists on cluster nodes (Human Instruction)
- [x] 2. Create `workloads/jellyfin/` directory with deployment manifests
- [x] 3. Define a PVC for media storage using `synology-nfs` StorageClass (ReadWriteMany)
- [x] 4. Define a PVC for config storage using Longhorn StorageClass (ReadWriteOnce)
- [x] 5. Create a Deployment with the Jellyfin container, mounting both PVCs
- [x] 6. Configure GPU device passthrough (`/dev/dri/renderD128`) for hardware transcoding
- [x] 7. Create a Service (ClusterIP) for Jellyfin on port 8096
- [x] 8. Create an IngressRoute (Traefik) with TLS for external access
- [ ] 9. Verify ArgoCD syncs the Jellyfin application
- [ ] 10. Verify Jellyfin is accessible via the ingress URL
- [ ] 11. Complete initial Jellyfin setup wizard and confirm media library scanning works

---

## Components

```
  This repo
  ┌──────────────────────────────────────────────────┐
  │  workloads/jellyfin/                             │
  │  ├── deployment.yaml                             │
  │  ├── service.yaml                                │
  │  ├── ingress.yaml                                │
  │  ├── pvc-media.yaml        (synology-nfs)        │
  │  └── pvc-config.yaml       (longhorn)            │
  └──────────────────┬─────────────────────────────────┘
                     │ ArgoCD syncs (wave 5)
                     ▼
  ┌──────────────────────────────────────────────────┐
  │              k3s Cluster                         │
  │                                                  │
  │  namespace: jellyfin                             │
  │  ┌────────────────────────────────────────┐      │
  │  │   Jellyfin Deployment                  │      │
  │  │   ├── /config  ← Longhorn PVC          │      │
  │  │   ├── /media   ← Synology NFS PVC      │      │
  │  │   └── /dev/dri ← GPU passthrough       │      │
  │  └──────────────┬─────────────────────────┘      │
  │                 │                                 │
  │  ┌──────────────▼─────────────────────────┐      │
  │  │   Service :8096                        │      │
  │  │   IngressRoute (jellyfin.domain.com)   │      │
  │  └────────────────────────────────────────┘      │
  └──────────────────────────────────────────────────┘
           │ NFS                    │ iSCSI/replicated
           ▼                       ▼
  ┌─────────────────┐    ┌─────────────────┐
  │  Synology NAS   │    │    Longhorn     │
  │  /volume1/media │    │  (config data)  │
  └─────────────────┘    └─────────────────┘
```

---

## Success Criteria

- [ ] Jellyfin pod is `Running` in the `jellyfin` namespace
- [ ] Media PVC is bound and backed by Synology NFS
- [ ] Config PVC is bound and backed by Longhorn
- [ ] Jellyfin web UI is accessible via `https://jellyfin.yourdomain.com`
- [ ] TLS certificate is valid (issued by cert-manager)
- [ ] Hardware transcoding works (test by playing a file that requires transcoding; check Jellyfin dashboard for `(HW)` indicator)
- [ ] Media library scan discovers files placed on the NFS volume

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `docs/specs/synology-csi.md` | Synology CSI driver — provides the `synology-nfs` StorageClass for media storage |
| `docs/specs/longhorn.md` | Longhorn — provides storage for Jellyfin config and metadata |
| `docs/specs/traefik.md` | Traefik ingress controller — routes external traffic to Jellyfin |
| `docs/specs/cert-manager.md` | TLS certificates for the ingress |
| `docs/specs/metallb.md` | LoadBalancer IPs for Traefik |
| https://jellyfin.org/docs/ | Official Jellyfin documentation |
| https://jellyfin.org/docs/general/administration/hardware-acceleration/intel | Intel QuickSync transcoding setup |

---

## Design Decisions

### Decision: Single shared media PVC

**Options considered:**
- Separate PVCs per media type (movies, tv, music)
- Single PVC for all media

**Decision:** Single PVC. Jellyfin organizes media into libraries internally — the underlying
storage doesn't need to mirror that structure. A single PVC backed by the Synology `media`
shared folder keeps things simple. Subdirectories (`/media/movies`, `/media/tv`, etc.) can
be created within the volume.

**Trade-offs:** Less granular storage management, but simpler to maintain. The arr apps
will mount the same PVC and write into the appropriate subdirectories.

---

### Decision: Intel QuickSync over software transcoding

**Options considered:**
- Software transcoding (CPU only, no device passthrough needed)
- Intel QuickSync via `/dev/dri` passthrough

**Decision:** QuickSync. All cluster nodes have Intel CPUs with integrated graphics. Hardware
transcoding dramatically reduces CPU usage and enables multiple simultaneous transcodes.
The device is passed through to the container via `securityContext.privileged: false` with
a resource limit or direct `hostPath` device mount.

**Trade-offs:** Requires the `i915` driver to be loaded on nodes and the render device to
exist. Limits pod scheduling to nodes with the device (all nodes in this cluster, so not
a practical constraint). If a node lacks the device, the pod won't schedule there.

---

### Decision: Config on Longhorn, media on Synology

**Options considered:**
- All storage on Synology NFS
- Config and media on separate backends

**Decision:** Split storage. Jellyfin's config directory contains an SQLite database for
metadata, watch history, and user data. SQLite performs poorly on NFS due to locking
semantics. Longhorn provides local replicated SSD storage with proper POSIX semantics,
which is ideal for database files. Media files are large sequential reads that work
perfectly over NFS.

**Trade-offs:** Two PVCs to manage. The SQLite performance issue on NFS makes this
split necessary rather than optional.

---

### Decision: Plain manifests over Helm chart

**Options considered:**
- Use the unofficial Jellyfin Helm chart
- Write plain Kubernetes manifests

**Decision:** Plain manifests. Jellyfin's deployment is straightforward (single container,
two volumes, a service, an ingress). A Helm chart adds indirection without meaningful
value for this simple a workload. Plain manifests are easier to read and debug in a
homelab context.

**Trade-offs:** No templating for values. Acceptable since there's only one instance
and configuration is minimal.
