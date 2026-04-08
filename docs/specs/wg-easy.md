# WireGuard VPN (wg-easy)

## Executive Summary

Deploy wg-easy, a simple WireGuard VPN server with a web UI for managing peers. This provides inbound VPN access to the home network from anywhere, enabling access to LAN resources and homelab services when away from home. The web UI eliminates manual config file editing — peers are added with a click and joined via QR code from the WireGuard mobile app.

**Author:** Drew Locketz
**Date:** 2026-04-07
**Status:** Draft

---

## Dependencies

| Spec | Why |
|---|---|
| `metallb.md` | LoadBalancer IP for the WireGuard UDP endpoint |
| `traefik.md` | Ingress for the admin web UI |
| `cert-manager.md` | TLS certificate for the admin UI |
| `longhorn.md` | Persistent storage for peer configs |
| `blocky.md` | DNS server to push to VPN clients |

---

## Human Instructions

These steps must be completed after deployment.

**1. Port forwarding on router**
- Forward UDP port 51820 from the internet to the WireGuard LoadBalancer IP (e.g. `10.0.4.242`)

**2. DNS**
- Use an existing dynamic DNS hostname that resolves to the home public IP. Set this as `WG_HOST` in the deployment env vars.

**3. Initial admin password**
- Set the bcrypt-hashed admin password via SealedSecret before first deployment

**4. Add the first peer**
- Open `https://wg.home.drewdevlab.com` (only from the LAN initially)
- Log in with the admin password
- Click "New Client", name it, and scan the QR code with the WireGuard mobile app

---

## Tasks

- [ ] 1. Create `workloads/wg-easy/` directory
- [ ] 2. Create `sealedsecret-admin.yaml` — SealedSecret with bcrypt-hashed admin password
- [ ] 3. Create `pvc-config.yaml` — Longhorn PVC for peer config storage (1Gi)
- [ ] 4. Create `deployment.yaml` — `ghcr.io/wg-easy/wg-easy` container with `NET_ADMIN` capability, host-level sysctl settings for IP forwarding, env vars for WireGuard host, port, and DNS
- [ ] 5. Create `service-vpn.yaml` — LoadBalancer service exposing UDP 51820 via MetalLB annotation
- [ ] 6. Create `service-ui.yaml` — ClusterIP service exposing the web UI on port 51821
- [ ] 7. Create `ingress.yaml` — Traefik IngressRoute for `wg.home.drewdevlab.com` with wildcard TLS
- [ ] 8. Verify ArgoCD syncs the wg-easy application (auto-discovered by workloads ApplicationSet)
- [ ] 9. Verify the wg-easy pod is `Running`
- [ ] 10. Verify the web UI is accessible at `https://wg.home.drewdevlab.com`
- [ ] 11. Verify UDP 51820 is reachable from outside the network (after port forwarding is configured)
- [ ] 12. Add a test peer and verify full LAN access + DNS resolution for `*.home.drewdevlab.com`

> Agents: check off each task as it is completed.

---

## Components

```
  Internet
  ┌──────────────────────────────────────────────────┐
  │  Mobile device / laptop (WireGuard client)       │
  │  DNS: 10.0.4.241 (Blocky, pushed by wg-easy)     │
  │  AllowedIPs: 10.0.0.0/16                         │
  └──────────────────┬───────────────────────────────┘
                     │ UDP 51820 (encrypted)
                     ▼
  ┌──────────────────────────────────────────────────┐
  │  Home router                                     │
  │  Port forward: UDP 51820 → 10.0.4.242            │
  └──────────────────┬───────────────────────────────┘
                     │
                     ▼
  ┌──────────────────────────────────────────────────┐
  │              k3s Cluster                         │
  │                                                  │
  │  namespace: wg-easy                              │
  │  ┌────────────────────────────────────────┐      │
  │  │   wg-easy pod (NET_ADMIN)              │      │
  │  │   ├── WireGuard server                 │      │
  │  │   ├── Admin web UI (port 51821)        │      │
  │  │   └── Longhorn PVC /etc/wireguard      │      │
  │  └──────┬──────────────────────┬──────────┘      │
  │         │                      │                  │
  │  ┌──────▼─────────┐   ┌────────▼──────────┐      │
  │  │ Service (LB)   │   │ Service (ClusterIP)│      │
  │  │ UDP :51820     │   │ TCP :51821         │      │
  │  │ 10.0.4.242     │   │                    │      │
  │  └────────────────┘   └──────┬─────────────┘      │
  │                              │                    │
  │                       ┌──────▼──────────┐         │
  │                       │  IngressRoute    │         │
  │                       │  wg.home.drewdev │         │
  │                       └──────────────────┘         │
  │                                                    │
  │  VPN clients route to full LAN (10.0.0.0/16)      │
  │  and resolve DNS via Blocky (10.0.4.241)          │
  └──────────────────────────────────────────────────┘
```

---

## Key Configuration

### Environment Variables (in deployment.yaml)

```yaml
- name: WG_HOST
  value: <existing-dyndns-hostname>  # existing DDNS hostname resolving to home public IP
- name: WG_PORT
  value: "51820"
- name: WG_DEFAULT_DNS
  value: "10.0.4.241"                # Blocky DNS
- name: WG_DEFAULT_ADDRESS
  value: "10.8.0.x"                  # VPN client subnet
- name: WG_ALLOWED_IPS
  value: "10.0.0.0/16"               # full LAN access
- name: PASSWORD_HASH
  valueFrom:
    secretKeyRef:
      name: wg-easy-admin
      key: password-hash
```

### Pod Security

- `securityContext.capabilities.add: ["NET_ADMIN", "SYS_MODULE"]`
- `sysctls`:
  - `net.ipv4.ip_forward=1`
  - `net.ipv4.conf.all.src_valid_mark=1`

---

## Success Criteria

- [ ] wg-easy pod is `Running` in the `wg-easy` namespace
- [ ] LoadBalancer service has IP `10.0.4.242` and UDP 51820 is listening
- [ ] Admin web UI accessible at `https://wg.home.drewdevlab.com`
- [ ] Port forwarding verified — UDP 51820 reachable from outside
- [ ] Test peer successfully connects from an external network
- [ ] Connected peer can reach LAN resources (e.g. SSH to `10.0.4.37`)
- [ ] Connected peer resolves `grafana.home.drewdevlab.com` via Blocky
- [ ] Peer configs persist across pod restarts (Longhorn PVC)

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `workloads/blocky/service-dns.yaml` | Reference for MetalLB LoadBalancer annotation pattern |
| `workloads/prowlarr/` | Reference for simple workload structure |
| `infrastructure/sealed-secrets/` | SealedSecret pattern reference |
| https://github.com/wg-easy/wg-easy | Official wg-easy project |

---

## Design Decisions

### Decision: wg-easy over bare WireGuard

**Options considered:**
- `linuxserver/wireguard` — bare WireGuard, manage peer configs manually
- `wg-easy` — WireGuard + web UI for peer management

**Decision:** wg-easy. Adding/removing peers via a web UI with QR code generation is significantly simpler than hand-editing config files, which matters most when setting up new mobile devices. The project is actively maintained and widely used.

**Trade-offs:** Adds a web UI that needs to be exposed and secured. Mitigated by putting it behind Traefik with TLS and an admin password.

### Decision: Full LAN access (10.0.0.0/16)

**Options considered:**
- Route only the cluster subnet (10.42.0.0/16)
- Route the full LAN (10.0.0.0/16)
- Route all traffic (0.0.0.0/0 — full tunnel)

**Decision:** Full LAN. The main reason to run a home VPN is to reach LAN devices (NAS, router admin, homelab services) — limiting to just the k3s subnet would leave out everything else. Full tunnel is unnecessary and would route all client traffic through the home connection.

**Trade-offs:** None meaningful for a trusted home network.

### Decision: Push Blocky as DNS to clients

**Options considered:**
- Don't push DNS — clients use their own resolvers (won't resolve `*.home.drewdevlab.com`)
- Push Blocky DNS (10.0.4.241) to clients

**Decision:** Push Blocky. One line of config (`WG_DEFAULT_DNS`) makes internal hostnames work transparently over the VPN with zero client configuration. Also gives clients ad-blocking for free.

**Trade-offs:** None. Clients on the VPN get better DNS than they'd have without it.

### Decision: LoadBalancer for WireGuard UDP, ClusterIP + Ingress for web UI

**Options considered:**
- Single LoadBalancer for both UDP 51820 and TCP 51821
- Separate services: LoadBalancer for UDP, ClusterIP + IngressRoute for UI

**Decision:** Separate services. The WireGuard UDP endpoint must be reachable by IP (not hostname) and needs a dedicated LoadBalancer IP. The web UI works better behind Traefik with TLS and the existing wildcard cert, accessed via hostname.

**Trade-offs:** Two service manifests instead of one. Worth it for proper TLS on the admin UI.

### Decision: Sealed secret for admin password

**Options considered:**
- No authentication (rely on network isolation)
- Plaintext password in deployment.yaml (unsafe, especially if repo goes public)
- SealedSecret with bcrypt-hashed password

**Decision:** SealedSecret. wg-easy accepts a bcrypt hash via `PASSWORD_HASH`. Sealed so it's safe to commit.

**Trade-offs:** Requires running `kubeseal` once. Standard pattern in this repo.
