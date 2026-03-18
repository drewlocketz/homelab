# ddclient — Dynamic DNS Updater

## Executive Summary

ddclient is a lightweight dynamic DNS client that keeps a Cloudflare DNS record in sync
with the home network's public IP address. This spec covers deploying ddclient as a
Kubernetes Deployment via ArgoCD, configured to update the wildcard A record
`*.home.drewdevlab.com` on Cloudflare every 5 minutes. Combined with router port
forwarding (80/443 → 10.0.4.240), this enables external access to all homelab services
through Traefik without a static public IP.

**Author:** Drew Locketz
**Date:** 2026-03-17
**Status:** Draft

---

## Tasks

### Secrets
- [ ] 1. Create (or reuse) a Cloudflare API token with DNS edit permissions for `drewdevlab.com`
- [ ] 2. Seal the Cloudflare API token as a SealedSecret in `infrastructure/ddclient/`

### Deploy
- [ ] 3. Create `infrastructure/ddclient/Chart.yaml` (wrapper Helm chart or plain manifests)
- [ ] 4. Create `infrastructure/ddclient/values.yaml` or templates with ddclient configuration
- [ ] 5. Configure ddclient to update `*.home.drewdevlab.com` via Cloudflare API every 5 minutes

### Validate
- [ ] 6. Verify ArgoCD syncs the `ddclient` Application
- [ ] 7. Verify the ddclient pod is `Running` in the `ddclient` namespace
- [ ] 8. Verify the Cloudflare DNS record updates to the current public IP
- [ ] 9. Configure router port forwarding: ports 80/443 → 10.0.4.240
- [ ] 10. Verify an external request to `https://jellyfin.home.drewdevlab.com` reaches Traefik

---

## Components

```
  Public Internet
  ┌─────────────────────────────────────────────────┐
  │  Client → DNS lookup: jellyfin.home.drewdevlab.com
  │        → resolves to public IP (e.g. 73.x.x.x) │
  └──────────────────────┬──────────────────────────┘
                         │
  Router                 ▼
  ┌─────────────────────────────────────────────────┐
  │  Port forward :80/:443 → 10.0.4.240 (Traefik)  │
  └──────────────────────┬──────────────────────────┘
                         │
  k3s Cluster            ▼
  ┌─────────────────────────────────────────────────┐
  │                                                 │
  │  namespace: ddclient                            │
  │  ┌───────────────────────────────────────────┐  │
  │  │  ddclient (Deployment)                    │  │
  │  │  └── every 5 min: update Cloudflare DNS   │  │
  │  │      *.home.drewdevlab.com → public IP    │  │
  │  └───────────────────────────────────────────┘  │
  │                                                 │
  │  namespace: traefik                             │
  │  ┌───────────────────────────────────────────┐  │
  │  │  Traefik @ 10.0.4.240                     │  │
  │  │  └── routes by hostname to services       │  │
  │  └───────────────────────────────────────────┘  │
  └─────────────────────────────────────────────────┘

  Cloudflare DNS
  ┌─────────────────────────────────────────────────┐
  │  *.home.drewdevlab.com → <public IP>            │
  │  (A record, DNS only / grey cloud)              │
  │  Updated by ddclient every 5 minutes            │
  └─────────────────────────────────────────────────┘
```

### Repo layout

```
infrastructure/ddclient/
├── Chart.yaml
├── values.yaml (or templates/)
└── sealedsecret-cloudflare-api-token.yaml
```

---

## Success Criteria

- [ ] ddclient pod `Running` in `ddclient` namespace
- [ ] Cloudflare A record for `*.home.drewdevlab.com` matches current public IP
- [ ] Record updates automatically when public IP changes
- [ ] External request to `https://jellyfin.home.drewdevlab.com` reaches Traefik and serves the app

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `docs/specs/traefik.md` | Traefik receives forwarded traffic and routes by hostname |
| `docs/specs/cert-manager.md` | TLS certificates for `*.home.drewdevlab.com` via Let's Encrypt |
| `docs/specs/sealed-secrets.md` | Cloudflare API token stored as a SealedSecret |
| `docs/specs/app-of-apps-structure.md` | ApplicationSet auto-generates the `ddclient` Application from `infrastructure/ddclient/` |
| https://ddclient.net/ | ddclient documentation |

---

## Design Decisions

### Decision: ddclient over Cloudflare Tunnel

**Options considered:**
- ddclient — updates DNS with current public IP; requires router port forwarding
- Cloudflare Tunnel — tunnels traffic through Cloudflare; no port forwarding needed
- external-dns — Kubernetes-native DNS controller; heavier, designed for dynamic service discovery

**Decision:** ddclient. It is lightweight, single-purpose, and well-understood. Cloudflare
Tunnel routes all traffic through Cloudflare's network, adding latency and a dependency on
their proxy infrastructure. ddclient keeps traffic direct: client → router → Traefik.

**Trade-offs:** Requires router port forwarding (80/443 → 10.0.4.240). Exposes those ports
on the home network. Acceptable for a homelab — the attack surface is limited to Traefik,
which only routes to known services.

---

### Decision: In-cluster Deployment over host-level service

**Options considered:**
- Run ddclient as a Kubernetes Deployment, managed by ArgoCD
- Run ddclient on the host (systemd service or Docker container outside k3s)

**Decision:** In-cluster. Follows the existing GitOps pattern — everything is declared in
this repo and synced by ArgoCD. Keeps operational consistency: one place to manage, monitor,
and update all services.

**Trade-offs:** If the cluster is down, DNS stops updating. Not a real concern — if the
cluster is down, the services are unreachable anyway.

---

### Decision: Wildcard A record over per-service records

**Options considered:**
- Individual A records per service (jellyfin, grafana, etc.)
- Single wildcard A record `*.home.drewdevlab.com`

**Decision:** Wildcard. Matches the existing Traefik and cert-manager setup. Adding a new
service only requires an IngressRoute — no DNS changes.

**Trade-offs:** All subdomains resolve to the same IP. Acceptable; Traefik differentiates
by hostname.

---

### Decision: 5-minute update interval

**Options considered:**
- 1 minute — very responsive, more API calls
- 5 minutes — good balance
- 30 minutes — low API usage, stale during IP changes

**Decision:** 5 minutes. Residential ISPs rarely change IPs more than once a day. 5 minutes
provides a reasonable worst-case downtime window without hammering the Cloudflare API.

**Trade-offs:** Up to 5 minutes of downtime after an IP change. Acceptable for a homelab.
