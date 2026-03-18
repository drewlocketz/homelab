# cert-manager

## Executive Summary

cert-manager is a Kubernetes-native certificate controller that automates the issuance
and renewal of TLS certificates. This spec covers deploying cert-manager via ArgoCD and
configuring it with a Cloudflare DNS-01 `ClusterIssuer` to obtain wildcard Let's Encrypt
certificates for `*.home.yourdomain.com`. The Cloudflare API token is stored as a
SealedSecret. Once deployed, any service can request a valid TLS certificate by
referencing the `ClusterIssuer` in its `IngressRoute` — no manual certificate management
required.

**Author:** Drew Locketz
**Date:** 2026-03-16
**Status:** Complete

---

## Tasks

### Secrets
- [ ] 1. Create a Cloudflare API token scoped to DNS edit permissions for your domain
- [ ] 2. Seal the Cloudflare API token as a SealedSecret in `infrastructure/cert-manager/`

### Deploy
- [x] 3. Add the cert-manager Helm chart source to `infrastructure/cert-manager/`
- [x] 4. Add a `ClusterIssuer` manifest for Let's Encrypt staging (for initial testing)
- [x] 5. Add a `ClusterIssuer` manifest for Let's Encrypt production
- [x] 6. Add a wildcard `Certificate` manifest for `*.home.yourdomain.com`
- [ ] 7. Verify ArgoCD syncs the `cert-manager` Application
- [ ] 8. Verify all cert-manager pods are `Running` in the `cert-manager` namespace

### Validate
- [ ] 9. Verify the staging `Certificate` is issued successfully
- [ ] 10. Switch to the production `ClusterIssuer` and verify the production certificate issues
- [ ] 11. Verify the wildcard certificate is stored as a Secret and usable by Traefik

---

## Components

```
  Cloudflare
  ┌───────────────────────────────────────────────┐
  │  DNS-01 challenge:                            │
  │  cert-manager creates _acme-challenge TXT     │
  │  record → Let's Encrypt validates → issues    │
  │  cert                                         │
  └──────────────┬────────────────────────────────┘
                 │ Cloudflare API token (SealedSecret)
                 ▼
  ┌───────────────────────────────────────────────┐
  │              k3s Cluster                      │
  │                                               │
  │  namespace: cert-manager                      │
  │  ┌─────────────────────────────────────────┐  │
  │  │  cert-manager controller                │  │
  │  │  cert-manager webhook                   │  │
  │  │  cert-manager cainjector               │  │
  │  └─────────────────────────────────────────┘  │
  │                                               │
  │  ClusterIssuer: letsencrypt-staging           │
  │  ClusterIssuer: letsencrypt-production        │
  │                                               │
  │  Certificate: *.home.yourdomain.com           │
  │  └── stored as Secret → used by Traefik       │
  └───────────────────────────────────────────────┘
```

### Certificate Issuance Flow

```
  cert-manager detects Certificate resource
           │
           ▼
  Creates CertificateRequest
           │
           ▼
  DNS-01 challenge: adds TXT record to
  Cloudflare via API token
           │
           ▼
  Let's Encrypt validates TXT record
           │
           ▼
  Certificate issued, stored as Secret
  in cluster (auto-renewed before expiry)
```

---

## Success Criteria

- [ ] All cert-manager pods `Running` in `cert-manager` namespace
- [ ] Staging `ClusterIssuer` shows `Ready`
- [ ] Production `ClusterIssuer` shows `Ready`
- [ ] Wildcard `Certificate` for `*.home.yourdomain.com` shows `Ready`
- [ ] Certificate Secret is present and contains a valid cert/key pair
- [ ] A Traefik `IngressRoute` using the certificate serves HTTPS without browser warnings

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `docs/specs/sealed-secrets.md` | Required — Cloudflare API token stored as a SealedSecret |
| `docs/specs/traefik.md` | cert-manager certificates are consumed by Traefik for TLS termination |
| `docs/specs/app-of-apps-structure.md` | ApplicationSet auto-generates the `cert-manager` Application from `infrastructure/cert-manager/` |
| https://cert-manager.io/docs/installation/helm/ | cert-manager Helm chart |
| https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/ | Cloudflare DNS-01 provider docs |

---

## Design Decisions

### Decision: DNS-01 challenge over HTTP-01

**Options considered:**
- HTTP-01 — Let's Encrypt makes an HTTP request to the domain to verify ownership
- DNS-01 — Let's Encrypt validates a TXT record added to the domain's DNS

**Decision:** DNS-01. HTTP-01 requires the cluster to be reachable from the public
internet, which exposes the homelab. DNS-01 only requires API access to Cloudflare —
the cluster never needs to be publicly accessible. DNS-01 also supports wildcard
certificates; HTTP-01 does not.

**Trade-offs:** Requires a Cloudflare API token with DNS edit permissions. Minor
security consideration — token is stored as a SealedSecret.

---

### Decision: Wildcard certificate over per-service certificates

**Options considered:**
- One `Certificate` per service (e.g., `grafana.home.yourdomain.com`)
- Single wildcard `Certificate` for `*.home.yourdomain.com`

**Decision:** Wildcard. Adding a new service requires no cert-manager changes —
Traefik picks up the existing wildcard cert automatically. Per-service certs also
hit Let's Encrypt rate limits faster if many services are added.

**Trade-offs:** All services share one certificate. If the cert is compromised, all
services are affected. Acceptable for a homelab.

---

### Decision: Staging issuer first, then production

**Options considered:**
- Go straight to production Let's Encrypt issuer
- Test with staging issuer first, switch to production once validated

**Decision:** Staging first. Let's Encrypt production has strict rate limits — if
something is misconfigured, hitting the production issuer repeatedly burns through
the weekly limit. Staging has much higher limits and is identical in behaviour
except the certificate is not browser-trusted.

**Trade-offs:** An extra step to switch from staging to production. Worth it to
avoid rate limit issues during initial setup.

---

### Decision: ClusterIssuer over Issuer

**Options considered:**
- `Issuer` — namespace-scoped, must be created in each namespace that needs certs
- `ClusterIssuer` — cluster-scoped, usable from any namespace

**Decision:** `ClusterIssuer`. All services across all namespaces can reference a
single `ClusterIssuer`. No need to create per-namespace Issuer objects.

**Trade-offs:** Slightly broader scope. Not a concern in a single-tenant homelab.
