# Longhorn

## Executive Summary

Longhorn is a distributed block storage system for Kubernetes that provides replicated
PersistentVolumes backed by local node disk. It runs entirely inside the cluster and
requires no external storage infrastructure. This spec covers installing node-level
prerequisites via the existing Ansible playbook, then deploying Longhorn via ArgoCD
as the storage backend for application databases and config. Media files and downloads
are handled separately by the Synology CSI driver.

**Author:** Drew Locketz
**Date:** 2026-03-16
**Status:** Complete

---

## Tasks

### Node prerequisites
- [x] 1. Update `bootstrap/group_vars/all.yml` to include `open-iscsi` and `nfs-common` in the extra packages list
- [ ] 2. Re-run the Ansible playbook against all nodes: `ansible-playbook -i bootstrap/inventory.yml bootstrap/k3s-ansible/site.yml`
- [ ] 3. Verify `iscsid` is active on all nodes: `ansible all -i bootstrap/inventory.yml -m shell -a "systemctl is-active iscsid" --become`

### Deploy Longhorn
- [x] 4. Add the Longhorn Helm chart source to `infrastructure/longhorn/`
- [ ] 5. Verify ArgoCD syncs the `longhorn` Application
- [ ] 6. Verify all Longhorn pods are `Running` in the `longhorn-system` namespace
- [ ] 7. Verify the `longhorn` StorageClass is present and set as default
- [ ] 8. Verify a test PVC binds and a pod can read/write to it

---

## Components

```
  This repo
  ┌──────────────────────────────────────┐
  │  infrastructure/longhorn/            │
  │  ├── Chart.yaml                      │
  │  └── values.yaml                     │
  └──────────────┬───────────────────────┘
                 │ ArgoCD syncs
                 ▼
  ┌──────────────────────────────────────────────┐
  │                k3s Cluster                   │
  │                                              │
  │  namespace: longhorn-system                  │
  │  ┌──────────────────────────────────────┐    │
  │  │  Longhorn Manager  (DaemonSet)       │    │
  │  │  Longhorn Driver   (DaemonSet)       │    │
  │  │  Longhorn UI       (Deployment)      │    │
  │  └──────────────────────────────────────┘    │
  │                                              │
  │  StorageClass: longhorn (default)            │
  │  Replica count: 3 (one per node)             │
  │                                              │
  │  ┌──────┐   ┌──────┐   ┌──────┐             │
  │  │node 1│   │node 2│   │node 3│             │
  │  │ .26  │   │ .35  │   │ .21  │             │
  │  │/var/ │   │/var/ │   │/var/ │             │
  │  │lib/  │   │lib/  │   │lib/  │             │
  │  │long- │   │long- │   │long- │             │
  │  │horn  │   │horn  │   │horn  │             │
  │  └──────┘   └──────┘   └──────┘             │
  └──────────────────────────────────────────────┘
```

---

## Success Criteria

- [ ] All Longhorn pods are `Running` in `longhorn-system`
- [ ] `kubectl get storageclass` shows `longhorn` marked as default
- [ ] A test PVC using the `longhorn` StorageClass binds successfully with 3 replicas
- [ ] A pod mounting the test PVC can read and write files

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `docs/specs/k3s-ansible-bootstrap.md` | Ansible playbook used to install node prerequisites |
| `docs/specs/app-of-apps-structure.md` | ApplicationSet structure — the `infrastructure` ApplicationSet auto-generates the `longhorn` Application from `infrastructure/longhorn/` |
| https://longhorn.io/docs/latest/deploy/install/install-with-helm/ | Official Longhorn Helm install docs |

---

## Design Decisions

### Decision: OS disk for Longhorn storage

**Options considered:**
- Dedicated data disks per node
- OS disk (default Longhorn path `/var/lib/longhorn`)

**Decision:** OS disk for now. Adding dedicated disks later is straightforward — Longhorn
supports adding extra disks per node through its UI or via node configuration. Starting
simple avoids needing to partition and mount additional disks before the cluster is useful.

**Trade-offs:** OS disk space is shared with the system. Monitor disk usage and add
dedicated disks when workloads grow.

---

### Decision: 3 replicas (default)

**Options considered:**
- 1 replica (no redundancy, maximises usable space)
- 2 replicas
- 3 replicas (default, survives one node failure)

**Decision:** 3 replicas. Matches the 3-node cluster and ensures a volume remains
accessible if one node goes down — consistent with the HA goals of the cluster.

**Trade-offs:** Uses 3x the disk space of the actual data. Acceptable for app config
and database sizes, which are small compared to media files.

---

### Decision: No backup target for now

**Options considered:**
- Configure Longhorn backups to Synology NAS over NFS
- No backup target

**Decision:** No backup target initially. Longhorn backups to NFS can be added later
by pointing Longhorn at an NFS share on the Synology NAS. Keeping it simple until
the full storage stack is in place.

**Trade-offs:** Longhorn volumes are not backed up externally. Acceptable for a homelab
during initial setup.
