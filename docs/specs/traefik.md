# Traefik Ingress Controller

## Executive Summary

Traefik is a cloud-native reverse proxy and ingress controller. This spec covers
deploying Traefik via ArgoCD, exposing it on a dedicated MetalLB IP (`10.0.4.240`),
and configuring it as the ingress controller for the cluster. All services will be
accessible via subdomains of `home.yourdomain.com` (replace with actual domain).
Traefik handles HTTP→HTTPS redirection and terminates TLS using certificates issued
by cert-manager. Traefik was disabled at k3s install time specifically for this
GitOps-managed deployment.

**Author:** Drew Locketz
**Date:** 2026-03-16
**Status:** Complete

---

## Tasks

- [x] 1. Add the Traefik Helm chart source to `infrastructure/traefik/`
- [x] 2. Configure the LoadBalancer service to request IP `10.0.4.240` from MetalLB
- [x] 3. Configure HTTP→HTTPS redirect middleware globally
- [ ] 4. Verify ArgoCD syncs the `traefik` Application
- [ ] 5. Verify Traefik pods are `Running` in the `traefik` namespace
- [ ] 6. Verify `10.0.4.240` is assigned to the Traefik LoadBalancer service
- [ ] 7. Add a Cloudflare DNS A record: `*.home.yourdomain.com → 10.0.4.240`
- [ ] 8. Verify a test `IngressRoute` resolves and serves traffic

---

## Components

```
  Cloudflare DNS
  ┌─────────────────────────────────────────────┐
  │  *.home.yourdomain.com → 10.0.4.240         │
  └─────────────────────────────┬───────────────┘
                                │
  Home Network                  ▼
  ┌─────────────────────────────────────────────┐
  │  10.0.4.240  (MetalLB — Traefik)            │
  └─────────────────────────────┬───────────────┘
                                │
                                ▼
  ┌─────────────────────────────────────────────┐
  │              k3s Cluster                    │
  │                                             │
  │  namespace: traefik                         │
  │  ┌───────────────────────────────────────┐  │
  │  │  Traefik (Deployment)                 │  │
  │  │  ├── :80  → redirect to :443          │  │
  │  │  └── :443 → route by hostname         │  │
  │  └───────────────┬───────────────────────┘  │
  │                  │ IngressRoute              │
  │      ┌───────────┼───────────┐              │
  │      ▼           ▼           ▼              │
  │  grafana    argocd-ui    jellyfin ...        │
  └─────────────────────────────────────────────┘
```

---

## Success Criteria

- [ ] Traefik pods `Running` in `traefik` namespace
- [ ] LoadBalancer service assigned IP `10.0.4.240`
- [ ] `*.home.yourdomain.com` resolves to `10.0.4.240` from home network
- [ ] HTTP requests redirect to HTTPS
- [ ] A test service is reachable via `https://test.home.yourdomain.com`

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `docs/specs/metallb.md` | Required — MetalLB must be deployed to assign `10.0.4.240` to the Traefik service |
| `docs/specs/cert-manager.md` | Required for TLS — cert-manager issues certificates consumed by Traefik |
| `docs/specs/app-of-apps-structure.md` | ApplicationSet auto-generates the `traefik` Application from `infrastructure/traefik/` |
| https://doc.traefik.io/traefik/getting-started/install-traefik/#use-the-helm-chart | Traefik Helm chart |

---

## Design Decisions

### Decision: Traefik over Nginx ingress

**Options considered:**
- Nginx ingress controller — widely used, large community
- Traefik — cloud-native, native CRD support, built-in dashboard

**Decision:** Traefik. It was already planned as the ingress controller from the start
(disabled at k3s install time to be managed here). Traefik's `IngressRoute` CRDs are
more expressive than standard `Ingress` objects and it has a built-in dashboard for
visibility. Native middleware support (redirects, auth, rate limiting) is useful for
homelab services.

**Trade-offs:** Traefik CRDs are not portable to other ingress controllers. Acceptable
since we're not planning to swap ingress controllers.

---

### Decision: Fixed MetalLB IP via annotation

**Options considered:**
- Let MetalLB assign any available IP from the pool
- Pin Traefik to a specific IP (`10.0.4.240`) via `metallb.universe.tf/loadBalancerIPs` annotation

**Decision:** Pin to `10.0.4.240`. The Cloudflare DNS wildcard record must point to a
stable IP. If the IP changes, all services become unreachable until DNS is updated.

**Trade-offs:** Requires manually ensuring `10.0.4.240` is not already in use.

---

### Decision: Wildcard DNS record (`*.home.yourdomain.com`)

**Options considered:**
- Individual DNS records per service
- Wildcard DNS record pointing all subdomains at Traefik

**Decision:** Wildcard. Adding a new service requires only an `IngressRoute` manifest —
no DNS changes needed. Traefik routes by hostname internally.

**Trade-offs:** All subdomains of `home.yourdomain.com` resolve to `10.0.4.240`
regardless of whether a service exists, which could be mildly confusing. Not a real
concern in practice.
