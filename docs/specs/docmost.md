# Docmost Collaborative Wiki

## Executive Summary

Deploy Docmost as a self-hosted collaborative wiki and documentation platform —
an open-source alternative to Notion. Docmost provides real-time collaboration,
rich-text editing, nested pages, and workspace organization. It will be backed by
a CloudNativePG PostgreSQL database and a Redis instance for caching/sessions,
with local storage for file uploads. The end state is a fully functional wiki
accessible at `https://docs.home.drewdevlab.com`.

**Author:** Drew Locketz
**Date:** 2026-05-09
**Status:** Draft

---

## Dependencies

This spec cannot be implemented until the following specs are complete:

| Spec | Why |
|---|---|
| `longhorn.md` | Database and Redis PVCs require Longhorn storage |
| `traefik.md` | Ingress for web access |
| `cert-manager.md` | TLS certificate for the ingress |
| `metallb.md` | LoadBalancer IP for Traefik |
| `cloudnative-pg.md` | CloudNativePG operator must be installed before creating a Cluster CR |

---

## Human Instructions

These steps must be completed after deployment.

**1. DNS record**
- `docs.home.drewdevlab.com` should already resolve via the `*.home.drewdevlab.com`
  wildcard DNS record pointing to the Traefik LoadBalancer IP. Verify it resolves.

**2. Initial setup**
- Open `https://docs.home.drewdevlab.com`
- Create the initial workspace and admin account

**3. Generate APP_SECRET**
- Run `openssl rand -hex 32` to generate a 32-byte secret
- Seal it with `kubeseal` and commit the SealedSecret to the repo

---

## Tasks

- [ ] 1. Create `workloads/docmost/` directory
- [ ] 2. Create `sealedsecret-docmost.yaml` — SealedSecret containing `APP_SECRET` (generated via `openssl rand -hex 32`)
- [ ] 3. Create `cluster-db.yaml` — CloudNativePG `Cluster` CR (2 instances for HA, Longhorn storage, 10Gi, database `docmost`, owner `docmost`)
- [ ] 4. Create `redis.yaml` — Redis Deployment + Service (redis:8, appendonly persistence, Longhorn PVC 1Gi)
- [ ] 5. Create `pvc-storage.yaml` — Longhorn PVC (10Gi) for Docmost file uploads (`/app/data/storage`)
- [ ] 6. Create `deployment.yaml` — `docmost/docmost:0.70.2` container configured with environment variables for PostgreSQL (from CNPG app secret), Redis, APP_SECRET (from SealedSecret), and local storage driver. Recreate strategy.
- [ ] 7. Create `service.yaml` — ClusterIP on port 3000
- [ ] 8. Create `ingress.yaml` — Traefik IngressRoute for `docs.home.drewdevlab.com` with wildcard TLS
- [ ] 9. Verify ArgoCD syncs the docmost application (auto-discovered by workloads ApplicationSet)
- [ ] 10. Verify Docmost is accessible via the ingress URL
- [ ] 11. Complete initial workspace setup

> Agents: check off each task as it is completed.

---

## Components

```
  This repo
  ┌──────────────────────────────────────────────────────┐
  │  workloads/docmost/                                  │
  │  ├── sealedsecret-docmost.yaml  (APP_SECRET)         │
  │  ├── cluster-db.yaml            (CNPG Cluster CR)    │
  │  ├── redis.yaml                 (Deployment+Service) │
  │  ├── pvc-storage.yaml           (file uploads)       │
  │  ├── deployment.yaml            (Docmost)            │
  │  ├── service.yaml                                    │
  │  └── ingress.yaml                                    │
  └──────────────────┬───────────────────────────────────┘
                     │ ArgoCD syncs
                     ▼
  ┌──────────────────────────────────────────────────────┐
  │              k3s Cluster                             │
  │                                                      │
  │  namespace: docmost                                  │
  │  ┌────────────────────────────────────────────┐      │
  │  │  CNPG Cluster: docmost-db (2 instances)   │      │
  │  │  ├── PVC managed by CNPG (Longhorn)       │      │
  │  │  ├── Service: docmost-db-rw :5432         │      │
  │  │  └── Secret: docmost-db-app (auto-gen)    │      │
  │  └──────────────┬─────────────────────────────┘      │
  │                 │ :5432                               │
  │  ┌──────────────┼────────────────────────────┐       │
  │  │  Redis       │                            │       │
  │  │  :6379       │                            │       │
  │  │  PVC: 1Gi    │                            │       │
  │  └──────┬───────┘                            │       │
  │         │                                    │       │
  │  ┌──────▼───────────────▼────────────────────┐      │
  │  │   Docmost Deployment                      │      │
  │  │   ├── DB creds from docmost-db-app secret │      │
  │  │   ├── APP_SECRET from SealedSecret        │      │
  │  │   ├── Redis via redis://redis:6379        │      │
  │  │   └── /app/data/storage (PVC, 10Gi)       │      │
  │  └──────────────┬─────────────────────────────┘      │
  │                 │                                     │
  │  ┌──────────────▼─────────────────────────────┐      │
  │  │   Service :3000                            │      │
  │  │   IngressRoute (docs.home.drewdevlab.com)  │      │
  │  └────────────────────────────────────────────┘      │
  └──────────────────────────────────────────────────────┘
```

---

## Success Criteria

- [ ] CNPG Cluster `docmost-db` reports `Cluster in healthy state`
- [ ] CNPG-managed PVC is bound and backed by Longhorn
- [ ] Redis pod is `Running` with persistent storage
- [ ] Docmost pod is `Running` in the `docmost` namespace
- [ ] Docmost is connected to PostgreSQL (check logs for successful DB connection)
- [ ] Docmost is connected to Redis (check logs)
- [ ] Docmost web UI is accessible via `https://docs.home.drewdevlab.com`
- [ ] TLS certificate is valid (wildcard cert from cert-manager)
- [ ] Workspace creation wizard loads on first visit
- [ ] File uploads work (stored on Longhorn PVC)

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `workloads/n8n/` | Reference workload with CNPG database — closest template |
| `workloads/jellyseerr/` | Reference for simple workload pattern |
| `docs/specs/n8n.md` | Reference spec for a workload with PostgreSQL |
| `docs/specs/sso.md` | SSO spec — Docmost will be a Tier 1 (ForwardAuth) service since OIDC requires enterprise license |
| https://docmost.com/docs/installation | Official Docmost installation guide |
| https://docmost.com/docs/self-hosting/environment-variables | Full environment variable reference |
| https://github.com/docmost/docmost/blob/main/docker-compose.yml | Official docker-compose reference |
| https://hub.docker.com/r/docmost/docmost | Docker Hub — pinned to 0.70.2 |

---

## Design Decisions

### Decision: PostgreSQL via CloudNativePG

**Options considered:**
- Plain PostgreSQL Deployment (manual container + PVC + secret)
- CloudNativePG operator (Cluster CR)

**Decision:** CloudNativePG, consistent with n8n and other database-backed
workloads. The operator manages the PostgreSQL lifecycle (PVC provisioning,
credential secrets, health checks, HA replication) via a single `Cluster` CR.

**Trade-offs:** Requires the CNPG operator to be installed cluster-wide first.
Already deployed for n8n, so no additional overhead.

---

### Decision: Dedicated Redis deployment per-workload

**Options considered:**
- Shared Redis instance across all workloads
- Dedicated Redis deployment within the Docmost namespace

**Decision:** Dedicated Redis in the `docmost` namespace. Docmost is currently the
only workload that needs Redis. A shared instance would add cross-namespace
complexity and a single point of failure for no benefit. If future workloads need
Redis, revisit whether a shared instance or Redis operator makes sense.

**Trade-offs:** Slightly more resource usage than sharing. Minimal — a single
Redis instance uses ~25MB RAM.

---

### Decision: Local storage over S3 for file uploads

**Options considered:**
- Local storage (`STORAGE_DRIVER=local`) backed by a Longhorn PVC
- S3-compatible storage (e.g., MinIO or Synology S3)

**Decision:** Local storage on a Longhorn PVC. There is no S3-compatible storage
deployed in the cluster, and adding MinIO just for Docmost file uploads is
overkill. Longhorn provides replication across nodes for durability. 10Gi is
generous for a personal wiki.

**Trade-offs:** File uploads are tied to the PVC rather than an object store.
If Docmost scales to multiple replicas, local storage won't work — but that's
not a concern for a single-instance homelab deployment.

---

### Decision: Plain manifests over Helm chart

**Options considered:**
- Write plain Kubernetes manifests
- Use a community Helm chart

**Decision:** Plain manifests, consistent with all other workloads in this repo.
Docmost's deployment is straightforward (single container + Redis + database),
and there is no official Helm chart from the Docmost project.

**Trade-offs:** No templating for values. Acceptable for a single-instance
deployment.

---

### Decision: Recreate deployment strategy

**Options considered:**
- RollingUpdate (default)
- Recreate

**Decision:** Recreate. Docmost should not run multiple instances against the same
database simultaneously. Recreate ensures only one instance is active at a time.

**Trade-offs:** Brief downtime during rollouts, acceptable for a homelab.

---

### Decision: ForwardAuth for SSO instead of native OIDC

**Options considered:**
- Native OIDC integration within Docmost
- Traefik ForwardAuth via Authentik (from SSO spec)

**Decision:** ForwardAuth (Tier 1 in the SSO spec). Docmost's OIDC and SAML
support requires an enterprise license. ForwardAuth protects the application at
the ingress layer without needing any enterprise features.

**Trade-offs:** No user identity mapping from the IdP into Docmost — all users
authenticate at the Traefik layer but still need a separate Docmost account.
Acceptable for a small homelab with few users.

---

### Decision: Subdomain `docs` over `docmost` or `wiki`

**Options considered:**
- `docmost.home.drewdevlab.com`
- `docs.home.drewdevlab.com`
- `wiki.home.drewdevlab.com`

**Decision:** `docs.home.drewdevlab.com`. Short, memorable, and describes the
function rather than the tool. If Docmost is ever replaced, the URL stays
relevant.

**Trade-offs:** None.
