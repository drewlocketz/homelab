# n8n Workflow Automation

## Executive Summary

Deploy n8n as a workflow automation platform in the homelab. n8n is a self-hosted, node-based workflow automation tool that connects APIs, services, and triggers to build automated workflows. It will provide a web UI for building and managing automations, backed by a dedicated PostgreSQL database for reliable data storage.

**Author:** Drew Locketz
**Date:** 2026-03-20
**Status:** Draft

---

## Dependencies

This spec cannot be implemented until the following specs are complete:

| Spec | Why |
|---|---|
| `longhorn.md` | Database PVC requires Longhorn storage |
| `traefik.md` | Ingress for web access |
| `cert-manager.md` | TLS certificate for the ingress |
| `metallb.md` | LoadBalancer IP for Traefik |
| `cloudnative-pg.md` | CloudNativePG operator must be installed before creating a Cluster CR |

---

## Human Instructions

These steps must be completed after deployment.

**1. DNS record**
- Create a DNS record for `n8n.home.drewdevlab.com` pointing to the Traefik LoadBalancer IP

**2. Initial setup**
- Open `https://n8n.home.drewdevlab.com`
- Create the initial owner account (email + password)

---

## Tasks

- [ ] 1. Create `workloads/n8n/` directory
- [ ] 2. Create `cluster-db.yaml` — CloudNativePG `Cluster` CR (2 instances for HA, Longhorn storage, 5Gi, database `n8n`, owner `n8n`)
- [ ] 3. Create `deployment.yaml` — `n8nio/n8n` container configured to connect to the CNPG cluster using the app credential secret, Recreate strategy
- [ ] 4. Create `service.yaml` — ClusterIP on port 5678
- [ ] 5. Create `ingress.yaml` — Traefik IngressRoute for `n8n.home.drewdevlab.com` with wildcard TLS
- [ ] 6. Create `podmonitor.yaml` — PodMonitor for n8n Prometheus metrics (port 5678, path `/metrics`) with `release: monitoring` label
- [ ] 7. Verify ArgoCD syncs the n8n application (auto-discovered by workloads ApplicationSet)
- [ ] 8. Verify n8n is accessible via the ingress URL
- [ ] 9. Verify Prometheus is scraping n8n metrics

> Agents: check off each task as it is completed.

---

## Components

```
  This repo
  ┌──────────────────────────────────────────────────┐
  │  workloads/n8n/                                  │
  │  ├── cluster-db.yaml        (CNPG Cluster CR)    │
  │  ├── deployment.yaml        (n8n)                │
  │  ├── service.yaml                                │
  │  ├── ingress.yaml                                │
  │  └── podmonitor.yaml        (Prometheus metrics) │
  └──────────────────┬───────────────────────────────┘
                     │ ArgoCD syncs
                     ▼
  ┌──────────────────────────────────────────────────┐
  │              k3s Cluster                         │
  │                                                  │
  │  namespace: n8n                                  │
  │  ┌────────────────────────────────────────┐      │
  │  │   CNPG Cluster: n8n-db (2 instances)  │      │
  │  │   ├── PVC managed by CNPG (Longhorn)  │      │
  │  │   ├── Service: n8n-db-rw :5432        │      │
  │  │   └── Secret: n8n-db-app (auto-gen)   │      │
  │  └──────────────┬─────────────────────────┘      │
  │                 │ :5432                           │
  │  ┌──────────────▼─────────────────────────┐      │
  │  │   n8n Deployment                      │      │
  │  │   (creds from n8n-db-app secret)      │      │
  │  └──────────────┬─────────────────────────┘      │
  │                 │                                 │
  │  ┌──────────────▼─────────────────────────┐      │
  │  │   Service :5678                        │      │
  │  │   IngressRoute (n8n.home...)           │      │
  │  └────────────────────────────────────────┘      │
  │                                                  │
  │  n8n can reach any in-cluster service:           │
  │  ┌──────────┐ ┌──────────┐ ┌──────────┐         │
  │  │  Sonarr  │ │  Radarr  │ │ Jellyfin │  ...    │
  │  └──────────┘ └──────────┘ └──────────┘         │
  └──────────────────────────────────────────────────┘
```

---

## Success Criteria

- [ ] CNPG Cluster `n8n-db` reports `Cluster in healthy state`
- [ ] CNPG-managed PVC is bound and backed by Longhorn
- [ ] n8n pod is `Running` in the `n8n` namespace
- [ ] n8n is connected to PostgreSQL (check logs for successful DB connection)
- [ ] n8n web UI is accessible via `https://n8n.home.drewdevlab.com`
- [ ] TLS certificate is valid (wildcard cert from cert-manager)
- [ ] Account creation wizard loads on first visit
- [ ] n8n can reach other in-cluster services (e.g. create a test workflow hitting an internal URL)

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `workloads/jellyseerr/` | Reference for config-only workload pattern |
| `workloads/prowlarr/` | Reference for simple single-container workload |
| `docs/specs/jellyseerr.md` | Reference spec for a similar workload deployment |
| https://docs.n8n.io/hosting/installation/docker/ | Official n8n Docker installation docs |
| https://cloudnative-pg.io/documentation/ | CloudNativePG operator documentation |

---

## Design Decisions

### Decision: PostgreSQL via CloudNativePG

**Options considered:**
- SQLite (default, stored in data PVC)
- Plain PostgreSQL Deployment (manual container + PVC + secret)
- CloudNativePG operator (Cluster CR)

**Decision:** CloudNativePG. The operator manages the PostgreSQL lifecycle (PVC provisioning, credential secrets, health checks) via a single `Cluster` CR. This avoids hand-managing a Deployment, Service, PVC, and Secret for Postgres.

**Trade-offs:** Requires the CNPG operator to be installed cluster-wide first (separate spec/dependency). Worth it for reduced manifest complexity and operator-managed credentials.

### Decision: Recreate deployment strategy

**Options considered:**
- RollingUpdate (default)
- Recreate

**Decision:** Recreate. n8n does not support running multiple instances against the same database simultaneously. Recreate ensures only one instance is active at a time.

**Trade-offs:** Brief downtime during rollouts, acceptable for a homelab.

### Decision: Plain manifests over Helm chart

**Options considered:**
- Use the official n8n Helm chart
- Write plain Kubernetes manifests

**Decision:** Plain manifests, consistent with all other workloads. n8n's deployment is simple (single container, one volume, a service, an ingress).

**Trade-offs:** No templating for values. Acceptable for a single-instance deployment.

### Decision: Sync wave 6 (workloads tier)

**Options considered:**
- Wave 5 (alongside Jellyfin, Jellyseerr, Prowlarr)
- Wave 6 (alongside Sonarr, Radarr, etc.)

**Decision:** Wave 6. n8n is a workload with no ordering dependency on other workloads, but it benefits from all infrastructure being ready first.

**Trade-offs:** None meaningful.
