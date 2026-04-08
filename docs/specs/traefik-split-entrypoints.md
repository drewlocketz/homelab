# Traefik Split Public/Internal Entrypoints

## Executive Summary

Split Traefik ingress traffic across two MetalLB LoadBalancer IPs so that most homelab services become reachable only from inside the LAN or over the WireGuard VPN, while jellyfin and jellyseerr remain publicly accessible. The existing IP `10.0.4.240` stays as the **public** entrypoint (matching the current router port forwards for 80/443). A new IP `10.0.4.243` becomes the **internal** entrypoint for all admin/homelab services.

IngressRoutes opt in to an entrypoint by name. Blocky rewrites internal hostnames to the internal IP so VPN clients reach them directly, and jellyfin/jellyseerr continue to resolve via public DNS to the public IP.

**Author:** Drew Locketz
**Date:** 2026-04-07
**Status:** Draft

---

## Dependencies

| Spec | Why |
|---|---|
| `traefik.md` | The ingress controller being reconfigured |
| `metallb.md` | Provides the second LoadBalancer IP |
| `blocky.md` | Rewrites internal hostnames to the internal entrypoint IP |
| `wg-easy.md` | VPN clients use Blocky as their DNS to reach internal services |

---

## Goals

- Keep jellyfin and jellyseerr publicly reachable with no changes to Cloudflare DNS or router forwards.
- Make grafana, argocd, n8n, prowlarr, radarr, sonarr, sabnzbd, wg-easy UI, and any future admin UIs reachable **only** from the LAN or over VPN.
- Fail closed: a new IngressRoute that forgets to declare an entrypoint should not accidentally become public.

---

## Design

### Entrypoints

Traefik exposes two sets of web/websecure entrypoints, each bound to a distinct Kubernetes Service of `type: LoadBalancer`:

| Name | IP | Intended use | Router forwards |
|---|---|---|---|
| `web` / `websecure` (public) | `10.0.4.240` | Public services (jellyfin, jellyseerr) | 80/443 → 10.0.4.240 (existing, unchanged) |
| `web-internal` / `websecure-internal` | `10.0.4.243` | All admin + homelab services | None |

The public IP stays `10.0.4.240` so no router or Cloudflare DNS changes are required.

### Traefik Helm values

Add a second pair of entrypoints and a second service. Exact key names depend on the Traefik chart version already in use — the intent is:

- `ports.web` and `ports.websecure` continue to bind to the default service on `10.0.4.240`.
- Add `ports.web-internal` (port 80, expose on a new service) and `ports.websecure-internal` (port 443, TLS, expose on a new service).
- Define a second service entry (via `service.additionalServices` or equivalent) named `internal`, `type: LoadBalancer`, annotated with `metallb.universe.tf/loadBalancerIPs: 10.0.4.243`.
- Bind the `*-internal` ports to that new service so they get the new IP.

Both services share the same Traefik pods and the same wildcard TLS cert — only the listening IPs differ.

### IngressRoute changes

Every existing IngressRoute must be updated to explicitly declare its entrypoint:

**Public (jellyfin, jellyseerr):**
```yaml
spec:
  entryPoints:
    - websecure
```

**Internal (everything else — grafana, argocd, n8n, wg-easy, prowlarr, radarr, sonarr, sabnzbd, blocky if it has a UI, longhorn UI, etc.):**
```yaml
spec:
  entryPoints:
    - websecure-internal
```

Audit every file matching `workloads/*/ingress*.yaml` and `infrastructure/*/templates/*ingress*.yaml` during implementation. Any route that omits `entryPoints` today must be fixed — ambiguity here is how services leak to the public internet.

### Blocky customDNS

Update `workloads/blocky/configmap.yaml` to point all internal hostnames at `10.0.4.243` and to **omit** jellyfin/jellyseerr so they fall through to upstream (public) resolution:

```yaml
customDNS:
  customTTL: 1h
  filterUnmappedTypes: true
  mapping:
    home.drewdevlab.com: 10.0.4.243
    grafana.home.drewdevlab.com: 10.0.4.243
    argocd.home.drewdevlab.com: 10.0.4.243
    n8n.home.drewdevlab.com: 10.0.4.243
    wg.home.drewdevlab.com: 10.0.4.243
    prowlarr.home.drewdevlab.com: 10.0.4.243
    radarr.home.drewdevlab.com: 10.0.4.243
    sonarr.home.drewdevlab.com: 10.0.4.243
    sabnzbd.home.drewdevlab.com: 10.0.4.243
```

Clients using Blocky as DNS (LAN + VPN peers) get the internal IP. Clients resolving via public DNS get the public Cloudflare IP, which points at the public Traefik entrypoint — where only jellyfin/jellyseerr IngressRoutes are attached. Public visitors to `grafana.home.drewdevlab.com` hit Traefik on the public IP, find no matching route, and get a 404.

### Why this fails closed

An IngressRoute without an `entryPoints` field defaults to *all* entrypoints in Traefik. That is the current failure mode and the reason admin UIs leaked. Part of this spec is the one-time audit to ensure every route is explicit. Going forward, new IngressRoutes that omit the field will be publicly reachable — a lint rule or review checklist item should be added to catch this. (Not implemented in this spec; noted as a follow-up.)

---

## Human Instructions

None required at deploy time. Router forwards stay as they are. No Cloudflare DNS changes.

After deploy, **remove the 80/443 forward only if** you later decide to stop exposing jellyfin/jellyseerr too — not part of this spec.

---

## Implementation Tasks

1. **Traefik Helm values**: add the second service + internal entrypoints. Verify the chart version's syntax before editing.
2. **MetalLB**: confirm `10.0.4.243` is inside an existing address pool; extend the pool if not.
3. **Audit all IngressRoutes** under `workloads/` and `infrastructure/`. Add explicit `entryPoints:` to every one:
   - `websecure` → jellyfin, jellyseerr
   - `websecure-internal` → everything else
4. **Update `workloads/blocky/configmap.yaml`** with the mapping above.
5. **Sync + verify** (see below).

---

## Verification

**From a LAN or VPN client** (using Blocky as DNS):
```bash
dig grafana.home.drewdevlab.com +short        # → 10.0.4.243
dig jellyfin.home.drewdevlab.com +short       # → public Cloudflare IP
curl -I https://grafana.home.drewdevlab.com   # → 200/302 from Traefik
```

**From an external network** (cellular, no VPN):
```bash
curl -I https://jellyfin.home.drewdevlab.com  # → 200/302 (works)
curl -I https://grafana.home.drewdevlab.com   # → 404 from Traefik (no matching route on public entrypoint)
```

**MetalLB**:
```bash
kubectl get svc -n traefik                     # → two LoadBalancer svcs, IPs .240 and .243
```

**Traefik dashboard** should show both entrypoints and every route attached to exactly one of them.

---

## Open Questions

- Which Traefik chart is currently in use, and what is its exact syntax for declaring a second LoadBalancer service? Confirm during implementation before editing values.
- Should a pre-commit or CI lint rule be added to require explicit `entryPoints` on every IngressRoute? (Recommended, separate spec.)
