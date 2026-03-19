# SABnzbd with Gluetun VPN Sidecar

## Executive Summary

Deploy SABnzbd as a Usenet download client with all traffic routed through a ProtonVPN WireGuard tunnel via a gluetun sidecar container. SABnzbd and gluetun run in the same pod, sharing a network namespace so all SABnzbd download traffic is VPN-protected. Config is stored on Longhorn, downloads are written to a shared volume accessible by Sonarr and Radarr. The web UI is exposed via Traefik ingress with TLS.

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
| `sealed-secrets.md` | VPN credentials stored as a SealedSecret |
| Downloads volume migration spec (TBD) | Shared downloads PVC must exist before deployment |

---

## Human Instructions

These steps must be completed before or during deployment.

**1. DNS record**
- Create a DNS record for `sabnzbd.home.drewdevlab.com` pointing to the Traefik LoadBalancer IP

**2. Obtain ProtonVPN WireGuard credentials**
- Generate a WireGuard private key from the ProtonVPN dashboard (Settings > WireGuard)
- Note the private key — it will be sealed into a SealedSecret

**3. Create the SealedSecret**
- Create a Kubernetes Secret with the WireGuard private key, then seal it:
```bash
kubectl create secret generic sabnzbd-vpn \
  --namespace sabnzbd \
  --from-literal=WIREGUARD_PRIVATE_KEY=<your-private-key> \
  --dry-run=client -o yaml | kubeseal --format yaml > workloads/sabnzbd/sealedsecret-vpn.yaml
```

**4. Configure SABnzbd**
- On first launch, complete the SABnzbd setup wizard
- Add Usenet server credentials
- Configure categories for Sonarr and Radarr (e.g. `tv` → `/downloads/tv`, `movies` → `/downloads/movies`)

**5. Connect Sonarr and Radarr**
- In Sonarr/Radarr: Settings > Download Clients > Add SABnzbd
- Host: `sabnzbd.sabnzbd.svc.cluster.local`, Port: `8080`
- API Key: from SABnzbd UI (Config > General)

---

## Tasks

- [x] 1. Create `workloads/sabnzbd/` directory
- [x] 2. Create `pvc-config.yaml` — Longhorn PVC (ReadWriteOnce, 5Gi)
- [ ] 3. Create `sealedsecret-vpn.yaml` — SealedSecret with ProtonVPN WireGuard private key (Human Instruction)
- [x] 4. Create `deployment.yaml` — Pod with gluetun sidecar and SABnzbd container, Recreate strategy
- [x] 5. Create `service.yaml` — ClusterIP on port 8080
- [x] 6. Create `ingress.yaml` — Traefik IngressRoute for `sabnzbd.home.drewdevlab.com` with wildcard TLS
- [ ] 7. Verify ArgoCD syncs the SABnzbd application
- [ ] 8. Verify gluetun establishes VPN tunnel (check gluetun container logs)
- [ ] 9. Verify SABnzbd is accessible via the ingress URL

> Agents: check off each task as it is completed.

---

## Components

```
  This repo
  ┌──────────────────────────────────────────────────┐
  │  workloads/sabnzbd/                              │
  │  ├── deployment.yaml                             │
  │  ├── service.yaml                                │
  │  ├── ingress.yaml                                │
  │  ├── pvc-config.yaml        (longhorn)           │
  │  └── sealedsecret-vpn.yaml  (sealed-secrets)     │
  └──────────────────┬───────────────────────────────┘
                     │ ArgoCD syncs
                     ▼
  ┌──────────────────────────────────────────────────────┐
  │              k3s Cluster                             │
  │                                                      │
  │  namespace: sabnzbd                                  │
  │  ┌────────────────────────────────────────────────┐  │
  │  │   Pod (shared network namespace)               │  │
  │  │   ┌──────────────────────────────────────────┐ │  │
  │  │   │  gluetun container                       │ │  │
  │  │   │  ├── ProtonVPN WireGuard tunnel          │ │  │
  │  │   │  └── NET_ADMIN capability                │ │  │
  │  │   └──────────────────────────────────────────┘ │  │
  │  │   ┌──────────────────────────────────────────┐ │  │
  │  │   │  sabnzbd container                       │ │  │
  │  │   │  ├── /config     ← Longhorn PVC          │ │  │
  │  │   │  ├── /downloads  ← shared downloads PVC  │ │  │
  │  │   │  └── port 8080 (web UI)                  │ │  │
  │  │   └──────────────────────────────────────────┘ │  │
  │  └──────────────┬─────────────────────────────────┘  │
  │                 │                                     │
  │  ┌──────────────▼──────────────────────────────┐     │
  │  │   Service :8080                             │     │
  │  │   IngressRoute (sabnzbd.home...)            │     │
  │  └─────────────────────────────────────────────┘     │
  │                                                      │
  │  ┌──────────┐  ┌──────────┐                          │
  │  │  Sonarr  │  │  Radarr  │ ← read from /downloads  │
  │  └──────────┘  └──────────┘                          │
  └──────────────────────────────────────────────────────┘
         │ WireGuard tunnel
         ▼
  ┌─────────────────┐
  │   ProtonVPN     │
  └─────────────────┘
```

---

## Success Criteria

- [ ] SABnzbd pod is `Running` in the `sabnzbd` namespace with both containers healthy
- [ ] Config PVC is bound and backed by Longhorn
- [ ] Gluetun logs confirm VPN tunnel is established
- [ ] SABnzbd web UI is accessible via `https://sabnzbd.home.drewdevlab.com`
- [ ] TLS certificate is valid (wildcard cert from cert-manager)
- [ ] SABnzbd's public IP (shown in gluetun logs) differs from the cluster's public IP
- [ ] Downloads complete successfully through the VPN tunnel
- [ ] Sonarr and Radarr can connect to SABnzbd as a download client

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `workloads/jellyfin/` | Reference for plain-manifest workload pattern |
| `workloads/sonarr/deployment.yaml` | Reference for linuxserver.io container conventions |
| `infrastructure/sealed-secrets/` | SealedSecrets controller for encrypting VPN credentials |
| https://github.com/qdm12/gluetun-wiki | Gluetun documentation |
| https://github.com/qdm12/gluetun-wiki/blob/main/setup/providers/protonvpn.md | ProtonVPN-specific gluetun setup |
| https://docs.linuxserver.io/images/docker-sabnzbd/ | LinuxServer SABnzbd container docs |

---

## Design Decisions

### Decision: Gluetun sidecar vs standalone VPN pod

**Options considered:**
- Option A — Gluetun as a sidecar container in the SABnzbd pod
- Option B — Gluetun as a separate deployment with a shared network policy

**Decision:** Chose Option A. Sidecar containers share the pod's network namespace, meaning all SABnzbd traffic automatically routes through the VPN tunnel with no additional network configuration. This is simpler and more reliable than routing traffic between pods.

**Trade-offs:** The gluetun container restarts with SABnzbd on every rollout. If other apps later need VPN access, they'd need their own gluetun sidecar (or a refactor to a shared VPN pod). For now, only SABnzbd needs VPN.

### Decision: Recreate deployment strategy

**Options considered:**
- RollingUpdate (default)
- Recreate

**Decision:** Recreate. SABnzbd uses SQLite in the config PVC (RWO), same deadlock issue as Jellyfin and Prowlarr.

**Trade-offs:** Brief downtime during rollouts, acceptable for a homelab.

### Decision: SealedSecret for VPN credentials

**Options considered:**
- Manual kubectl secret (not committed)
- SealedSecret (encrypted, committed to repo)

**Decision:** SealedSecret. Consistent with the repo's GitOps approach — all resources are declared in the repo. The WireGuard private key is encrypted and safe to commit.

**Trade-offs:** Requires the sealed-secrets controller and `kubeseal` CLI for secret rotation.
