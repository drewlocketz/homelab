# Single Sign-On (SSO) for All Services

## Executive Summary

Deploy an SSO solution to provide centralized authentication across all homelab
services. Currently, services are either wide-open or rely on their own internal
auth with separate credentials. This spec adds an identity provider and wires it
into Traefik so that every service is behind a single login. The end state is:
one set of credentials, one login session, and no unauthenticated access to any
service from outside the cluster.

**Author:** Drew Locketz
**Date:** 2026-05-09
**Status:** Draft

---

## Tasks

- [ ] 1. Choose and deploy the identity provider (see Design Decisions)
- [ ] 2. Create a PostgreSQL database for the identity provider via CloudNativePG
- [ ] 3. Create SealedSecrets for IdP credentials, OIDC client secrets, and database password
- [ ] 4. Deploy the identity provider as a new infrastructure component (`infrastructure/authentik/`)
- [ ] 5. Add an ArgoCD Application for the identity provider (sync wave 4, after Traefik + cert-manager)
- [ ] 6. Create a Traefik ForwardAuth middleware pointing to the identity provider
- [ ] 7. Configure the IdP: create users, groups, and per-application OIDC providers/outposts
- [ ] 8. Add ForwardAuth middleware to all workload IngressRoutes (Tier 1 — proxy-only apps)
- [ ] 9. Configure native OIDC integration for apps that support it (Tier 2 — OIDC-capable apps)
- [ ] 10. Configure Jellyfin auth (Tier 3 — see Design Decisions)
- [ ] 11. Verify SSO login flow end-to-end for every service
- [ ] 12. Document manual IdP setup steps (user creation, OIDC provider config) in this spec

---

## Components

```
  Browser
  ┌──────────────────────────────────────────────────────────────┐
  │  https://sonarr.home.drewdevlab.com                         │
  └──────────────────────────────────┬───────────────────────────┘
                                     │
                                     ▼
  ┌──────────────────────────────────────────────────────────────┐
  │  Traefik (10.0.4.240)                                       │
  │                                                              │
  │  IngressRoute: sonarr.home.drewdevlab.com                   │
  │    middlewares:                                               │
  │      - authentik-forwardauth          ◄── NEW                │
  │    services:                                                  │
  │      - sonarr:8989                                           │
  └──────────────┬──────────────────┬────────────────────────────┘
                 │                  │
      ┌──────────▼──────┐   ┌──────▼──────────────────────┐
      │  ForwardAuth    │   │  Service (sonarr, etc.)     │
      │  (/outpost.goauthentik.io/auth/nginx)             │
      │  ┌──────────────▼──────────────────────────┐      │
      │  │  Authentik (identity provider)          │      │
      │  │  namespace: authentik                   │      │
      │  │                                         │      │
      │  │  ┌─────────────┐  ┌──────────────────┐ │      │
      │  │  │  Server     │  │  Embedded        │ │      │
      │  │  │  (web UI +  │  │  Outpost         │ │      │
      │  │  │   API)      │  │  (ForwardAuth    │ │      │
      │  │  │             │  │   endpoint)      │ │      │
      │  │  └──────┬──────┘  └──────────────────┘ │      │
      │  │         │                               │      │
      │  │  ┌──────▼──────┐                        │      │
      │  │  │ PostgreSQL  │                        │      │
      │  │  │ (CNPG)      │                        │      │
      │  │  └─────────────┘                        │      │
      │  └─────────────────────────────────────────┘      │
      └───────────────────────────────────────────────────┘

  Auth Flow (ForwardAuth — Tier 1):
  ─────────────────────────────────
  1. Request → Traefik
  2. Traefik calls ForwardAuth middleware → Authentik outpost
  3. If no session → redirect to Authentik login page
  4. User authenticates → session cookie set
  5. ForwardAuth returns 200 → Traefik forwards to upstream service

  Auth Flow (Native OIDC — Tier 2):
  ──────────────────────────────────
  1. User opens app → app redirects to Authentik OIDC authorize endpoint
  2. User authenticates → redirect back with auth code
  3. App exchanges code for token → user logged in natively
```

---

## Service Tiers

Services are grouped by how SSO is integrated:

### Tier 1 — ForwardAuth Only (no native OIDC support)

These apps have no OIDC/SAML support. Traefik's ForwardAuth middleware protects
them at the ingress layer. The app itself sees an already-authenticated request.

| Service    | Notes |
|------------|-------|
| Sonarr     | API key auth internally; ForwardAuth protects UI |
| Radarr     | Same as Sonarr |
| Prowlarr   | Same as Sonarr |
| Bazarr     | Same as Sonarr |
| SABnzbd    | Same as Sonarr |
| Blocky     | DNS admin UI |
| wg-easy    | VPN admin UI |

> **API bypass:** The *arr apps and SABnzbd communicate with each other via API
> keys. ForwardAuth must allow requests with valid API keys to pass through
> unauthenticated (match on `/api/` path or API key header).

### Tier 2 — Native OIDC

These apps support OIDC natively. Configure them as OIDC clients in Authentik
for a seamless login experience with proper user identity mapping.

| Service     | OIDC Support |
|-------------|-------------|
| Grafana     | Built-in OIDC support via `auth.generic_oauth` |
| n8n         | Built-in OIDC support via environment variables |
| ArgoCD      | Built-in OIDC/Dex support |
| Jellyseerr  | Built-in OIDC support |

### Tier 3 — Special Handling

| Service  | Notes |
|----------|-------|
| Jellyfin | Has its own user/permission system for libraries and parental controls. Use the Authentik Jellyfin SSO plugin for login federation, but keep Jellyfin's internal user management active. |

---

## Success Criteria

- [ ] Authentik is deployed and accessible at `https://auth.home.drewdevlab.com`
- [ ] A single admin user can log in to Authentik
- [ ] All Tier 1 services redirect to Authentik login when accessed unauthenticated
- [ ] All Tier 1 services are accessible after Authentik login without re-authenticating
- [ ] API traffic to Tier 1 services (e.g., Sonarr `/api/`) works without ForwardAuth
- [ ] All Tier 2 services use native OIDC login with Authentik
- [ ] Jellyfin login is federated through Authentik
- [ ] Session persists across services (single sign-on, not just single identity)
- [ ] Logging out of Authentik invalidates sessions across services
- [ ] All secrets (OIDC client secrets, DB passwords, Authentik secret key) are SealedSecrets

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `docs/specs/traefik.md` | Traefik is the ingress controller; ForwardAuth middleware is a Traefik feature |
| `docs/specs/sealed-secrets.md` | All SSO secrets must be SealedSecrets |
| `docs/specs/cloudnative-pg.md` | CloudNativePG operator for Authentik's PostgreSQL database |
| `infrastructure/traefik/` | Traefik deployment — middleware definitions will be added here or in Authentik's namespace |
| `workloads/*/ingress.yaml` | Each workload's IngressRoute — must be updated to reference ForwardAuth middleware |
| https://docs.goauthentik.io/docs/install-config/install/kubernetes | Authentik Helm chart for Kubernetes |
| https://docs.goauthentik.io/docs/providers/proxy/forward_auth | Authentik ForwardAuth (proxy provider) docs |
| https://doc.traefik.io/traefik/middlewares/http/forwardauth/ | Traefik ForwardAuth middleware reference |
| https://github.com/jellyfin/jellyfin-plugin-sso | Jellyfin SSO plugin for OIDC federation |

---

## Design Decisions

### Decision: Authentik over Authelia and Keycloak

**Options considered:**
- **Authelia** — Lightweight, Go-based, file/LDAP backend. Simple forward-auth proxy
  with basic OIDC provider support. Low resource footprint.
- **Authentik** — Full-featured identity provider. OIDC, SAML, LDAP, proxy provider
  (ForwardAuth), flows/policies engine, web UI for management. Requires PostgreSQL.
- **Keycloak** — Enterprise-grade IdP. Java-based, heavy resource usage. Full
  OIDC/SAML/LDAP support.

**Decision:** Authentik. It strikes the best balance for a homelab:
- Full OIDC provider with a polished admin UI for managing applications
- Built-in proxy outpost for ForwardAuth (no separate oauth2-proxy needed)
- Native Helm chart with good Kubernetes support
- CloudNativePG is already deployed, so the PostgreSQL requirement is free
- Active community with strong homelab adoption
- Lighter than Keycloak while being more capable than Authelia

**Trade-offs:** Heavier than Authelia (~512MB RAM for server + worker). Acceptable
given the cluster has sufficient resources and the OIDC provider capability is
valuable for Tier 2 apps. Authentik upgrades occasionally require database
migrations, which adds maintenance burden.

---

### Decision: ForwardAuth as default, native OIDC where supported

**Options considered:**
- ForwardAuth for everything — simplest, all auth at the ingress layer
- Native OIDC for everything — best UX, but many apps don't support it
- Hybrid — ForwardAuth for apps without OIDC, native OIDC where supported

**Decision:** Hybrid approach. ForwardAuth is the baseline for all services.
Apps with native OIDC support (Grafana, n8n, ArgoCD, Jellyseerr) also get OIDC
configured so they have proper user identity within the app (not just "someone
authenticated"). Tier 2 apps may still have ForwardAuth as a safety net.

**Trade-offs:** More configuration work upfront (one OIDC provider per Tier 2
app in Authentik). Worth it for proper user identity propagation.

---

### Decision: API path bypass for *arr apps

**Options considered:**
- ForwardAuth on all paths including `/api/` — breaks inter-service communication
- Exclude `/api/` paths from ForwardAuth — allows API key auth to work as-is
- Use separate IngressRoute for API paths without middleware

**Decision:** Exclude `/api/` paths from ForwardAuth using Traefik route matching.
Create two route rules per service: one for the UI (with ForwardAuth middleware)
and one for `/api/` paths (without). The *arr apps, SABnzbd, and Prowlarr
communicate heavily via API keys, and wrapping those in ForwardAuth would break
automation workflows.

**Trade-offs:** API endpoints are protected only by API keys, not SSO. This is
acceptable because API keys are long random strings and inter-service
communication is cluster-internal. External API access is also gated by the
VPN/network boundary.

---

### Decision: Embedded outpost over standalone outpost

**Options considered:**
- **Embedded outpost** — ForwardAuth endpoint runs inside the Authentik server process
- **Standalone outpost** — Separate deployment for the proxy/ForwardAuth endpoint

**Decision:** Start with the embedded outpost. It's simpler to deploy (no extra
pods) and sufficient for a homelab with a single user or small number of users.
Can migrate to a standalone outpost later if performance requires it.

**Trade-offs:** Embedded outpost shares resources with the Authentik server.
Not a concern at homelab scale.

---

### Decision: Jellyfin SSO via plugin rather than ForwardAuth-only

**Options considered:**
- ForwardAuth only — protects Jellyfin but doesn't map to Jellyfin users
- Jellyfin SSO plugin — federated login that maps Authentik users to Jellyfin users
- Replace Jellyfin auth entirely — not possible, Jellyfin needs internal users for permissions

**Decision:** Use the Jellyfin SSO plugin. Jellyfin's permission model (library
access, parental controls, transcoding limits) is tied to its internal user
system. The SSO plugin lets users log in via Authentik while preserving
Jellyfin's user-level permissions. ForwardAuth alone would bypass Jellyfin's
auth entirely, losing per-user controls.

**Trade-offs:** Requires installing and maintaining a third-party Jellyfin plugin.
The plugin must be kept in sync with Jellyfin updates.

---

### Decision: Sync wave 4 for Authentik deployment

**Options considered:**
- Sync wave 3 (alongside Traefik and cert-manager)
- Sync wave 4 (after Traefik and cert-manager)

**Decision:** Sync wave 4. Authentik needs both a working ingress (Traefik) and
valid TLS certificates (cert-manager) before it can serve its own UI and handle
OIDC flows. It also needs PostgreSQL from CloudNativePG (sync wave 3). Deploying
at wave 4 ensures all dependencies are ready.

**Trade-offs:** Adds a deployment ordering dependency. Acceptable since this
matches the natural dependency chain.
