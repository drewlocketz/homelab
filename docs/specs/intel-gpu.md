# Intel GPU Device Plugin for Hardware Transcoding

## Executive Summary

Jellyfin's hardware transcoding (Intel QuickSync/VAAPI) is broken because containerd mounts `/dev/dri` as read-only when using `hostPath` volumes, preventing FFmpeg from opening the render device. The fix is to deploy the Intel GPU device plugin, which handles device injection correctly and exposes GPUs as schedulable Kubernetes resources (`gpu.intel.com/i915`).

**Author:** Drew Locketz
**Date:** 2026-03-18
**Status:** Draft

---

## Tasks

- [ ] Create `infrastructure/intel-gpu/Chart.yaml` with Helm dependency on `intel-device-plugins-gpu`
- [ ] Create `infrastructure/intel-gpu/values.yaml` with shared device count and node selector
- [ ] Label GPU nodes: `kubectl label node k3s-node-0 k3s-node-1 k3s-node-2 intel.feature.node.kubernetes.io/gpu=true`
- [ ] Update `workloads/jellyfin/deployment.yaml` to use GPU resource limits instead of hostPath
- [ ] Verify GPU plugin DaemonSet is running
- [ ] Verify nodes advertise `gpu.intel.com/i915`
- [ ] Verify Jellyfin pod is Running and VAAPI works

---

## Components

```
  ┌──────────────────┐
  │  Intel GPU       │
  │  Device Plugin   │
  │  (DaemonSet)     │
  └────────┬─────────┘
           │ exposes gpu.intel.com/i915
           ▼
  ┌──────────────────┐        ┌──────────────────┐
  │  Kubernetes      │        │  Jellyfin Pod    │
  │  Scheduler       │───────>│  requests: 1 GPU │
  └──────────────────┘        └──────────────────┘
                                      │
                                      ▼
                              ┌──────────────────┐
                              │  /dev/dri/renderD │
                              │  (injected r/w)   │
                              └──────────────────┘
```

---

## Success Criteria

- [ ] Intel GPU device plugin DaemonSet is running on all labeled nodes
- [ ] `kubectl describe node` shows `gpu.intel.com/i915` as allocatable
- [ ] Jellyfin pod runs without `privileged: true` and without hostPath `/dev/dri`
- [ ] `vainfo` inside Jellyfin pod reports supported profiles
- [ ] Transcoding works in Jellyfin UI

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `workloads/jellyfin/deployment.yaml` | Current Jellyfin deployment with hostPath /dev/dri and privileged mode |
| `infrastructure/cert-manager/Chart.yaml` | Reference for Helm wrapper pattern used in this repo |
| https://intel.github.io/intel-device-plugins-for-kubernetes/cmd/gpu_plugin/README.html | Intel GPU plugin documentation |
| https://github.com/intel/helm-charts | Helm chart repository for Intel device plugins |

---

## Design Decisions

### Decision: Device plugin vs hostPath with privileged mode

**Options considered:**
- Option A — Intel GPU device plugin (DaemonSet) with resource requests
- Option B — hostPath `/dev/dri` with privileged security context

**Decision:** Chose Option A because the device plugin properly injects GPU devices read-write, integrates with the Kubernetes scheduler, and avoids running containers as privileged.

**Trade-offs:** Requires deploying an additional DaemonSet and labeling nodes, but eliminates the need for privileged containers and provides proper resource accounting.

### Decision: Shared device count

**Options considered:**
- `sharedDevNum: 1` — exclusive GPU access per pod
- `sharedDevNum: 10` — allow up to 10 pods to share each GPU

**Decision:** Chose `sharedDevNum: 10` to allow multiple workloads to share the GPU if needed in the future.

**Trade-offs:** Shared access means pods compete for GPU resources, but for a homelab with light transcoding this is acceptable.
