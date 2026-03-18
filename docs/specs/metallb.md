# MetalLB

## Executive Summary

MetalLB is a load balancer implementation for bare-metal Kubernetes clusters. Cloud
providers (GKE, EKS, etc.) supply a load balancer that assigns external IPs to
LoadBalancer services automatically — MetalLB does the same for a homelab. This spec
covers deploying MetalLB in L2 mode, which announces service IPs on the local network
using ARP. Once deployed, any service of type `LoadBalancer` receives an IP from the
configured pool. The primary consumer is Traefik, which gets a dedicated IP for HTTP/HTTPS.

**Author:** Drew Locketz
**Date:** 2026-03-16
**Status:** Complete

---

## Tasks

- [x] 1. Add the MetalLB Helm chart source to `infrastructure/metallb/`
- [x] 2. Add an `IPAddressPool` manifest defining the `10.0.4.240-10.0.4.250` range
- [x] 3. Add an `L2Advertisement` manifest to announce the pool over ARP
- [ ] 4. Verify ArgoCD syncs the `metallb` Application
- [ ] 5. Verify all MetalLB pods are `Running` in the `metallb-system` namespace
- [ ] 6. Verify a test LoadBalancer service receives an IP from the pool

---

## Components

```
  This repo
  ┌──────────────────────────────────────────────┐
  │  infrastructure/metallb/                     │
  │  ├── Chart.yaml                              │
  │  ├── values.yaml                             │
  │  ├── ipaddresspool.yaml                      │
  │  └── l2advertisement.yaml                    │
  └──────────────────┬───────────────────────────┘
                     │ ArgoCD syncs
                     ▼
  ┌──────────────────────────────────────────────┐
  │              k3s Cluster                     │
  │                                              │
  │  namespace: metallb-system                   │
  │  ┌────────────────────────────────────┐      │
  │  │  MetalLB controller                │      │
  │  │  MetalLB speaker  (DaemonSet)      │      │
  │  └────────────────────────────────────┘      │
  │                                              │
  │  IPAddressPool: 10.0.4.240-10.0.4.250        │
  │  L2Advertisement (ARP announcements)         │
  └──────────────────────────────────────────────┘
                     │ ARP
                     ▼
  ┌──────────────────────────────────────────────┐
  │           Home Network (Eero)                │
  │                                              │
  │  10.0.4.240 → Traefik                        │
  │  10.0.4.241 → (spare)                        │
  │  ...                                         │
  └──────────────────────────────────────────────┘
```

---

## Success Criteria

- [ ] All MetalLB pods `Running` in `metallb-system`
- [ ] A test `LoadBalancer` service receives an IP from `10.0.4.240-10.0.4.250`
- [ ] The IP is reachable from a device on the home network

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `docs/specs/app-of-apps-structure.md` | ApplicationSet auto-generates the `metallb` Application from `infrastructure/metallb/` |
| https://metallb.io/installation/helm/ | MetalLB Helm chart |

---

## Design Decisions

### Decision: L2 mode over BGP mode

**Options considered:**
- L2 mode — announces IPs via ARP on the local network, no router config needed
- BGP mode — peers with the router to announce routes, requires BGP-capable router

**Decision:** L2 mode. Eero does not support BGP. L2 mode works with any router and
requires zero network configuration outside the cluster.

**Trade-offs:** L2 mode has one limitation — only one node handles traffic for a given
IP at a time (the "leader" node). If that node goes down, MetalLB re-announces the IP
from another node. Failover takes a few seconds. Acceptable for a homelab.

---

### Decision: IP range 10.0.4.240-10.0.4.250

**Options considered:**
- Low range (10.0.4.10-10.0.4.20) — risk of DHCP conflict with Eero
- High range (10.0.4.240-10.0.4.250) — unlikely to be assigned by Eero's DHCP

**Decision:** High range. Eero assigns DHCP from the low end of the subnet. Picking
a high range minimises the risk of IP conflicts without requiring DHCP pool configuration
(which Eero does not expose).

**Trade-offs:** Not a hard reservation — if a device somehow gets assigned one of these
IPs by DHCP, there will be a conflict. Mitigated by using IPs well above the typical
DHCP assignment range.
