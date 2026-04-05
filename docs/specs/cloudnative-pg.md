# CloudNativePG Operator

## Executive Summary

Deploy the CloudNativePG (CNPG) operator to manage PostgreSQL clusters declaratively via Kubernetes custom resources. CNPG handles the full PostgreSQL lifecycle: provisioning, high availability with streaming replication, automatic failover, credential management, and backup orchestration. This operator is the foundation for any workload that needs a production-grade PostgreSQL database (e.g. n8n).

**Author:** Drew Locketz
**Date:** 2026-04-04
**Status:** Draft

---

## Dependencies

This spec cannot be implemented until the following specs are complete:

| Spec | Why |
|---|---|
| `longhorn.md` | PostgreSQL PVCs require Longhorn block storage |

---

## Tasks

- [ ] 1. Create `infrastructure/cloudnative-pg/Chart.yaml` — Helm chart wrapper for the CNPG operator (v0.28.0)
- [ ] 2. Create `infrastructure/cloudnative-pg/values.yaml` — operator configuration with monitoring enabled
- [ ] 3. Verify ArgoCD syncs the `cloudnative-pg` Application (auto-discovered by infrastructure ApplicationSet)
- [ ] 4. Verify the CNPG operator pod is `Running` in the `cloudnative-pg` namespace
- [ ] 5. Verify the `Cluster` CRD is installed (`kubectl get crds | grep cnpg`)

> Agents: check off each task as it is completed.

---

## Components

```
  This repo
  ┌──────────────────────────────────────────────────┐
  │  infrastructure/cloudnative-pg/                  │
  │  ├── Chart.yaml          (Helm wrapper)          │
  │  └── values.yaml         (operator config)       │
  └──────────────────┬───────────────────────────────┘
                     │ ArgoCD syncs
                     ▼
  ┌──────────────────────────────────────────────────┐
  │              k3s Cluster                         │
  │                                                  │
  │  namespace: cloudnative-pg                       │
  │  ┌────────────────────────────────────────┐      │
  │  │   CNPG Operator (controller-manager)  │      │
  │  │   ├── Watches for Cluster CRs         │      │
  │  │   ├── Manages PG pods + replication   │      │
  │  │   ├── Handles failover automatically  │      │
  │  │   └── Generates credential Secrets    │      │
  │  └────────────────────────────────────────┘      │
  │                                                  │
  │  CRDs installed:                                 │
  │  ├── Cluster          (PostgreSQL cluster)       │
  │  ├── Backup           (on-demand backup)         │
  │  ├── ScheduledBackup  (scheduled backups)        │
  │  └── Pooler           (PgBouncer connection pool)│
  │                                                  │
  │  Workloads create Cluster CRs in their own       │
  │  namespaces (e.g. n8n namespace):                │
  │  ┌────────────────────────────────────────┐      │
  │  │   Cluster: n8n-db (2 instances)       │      │
  │  │   ├── n8n-db-1 (primary)    :5432     │      │
  │  │   ├── n8n-db-2 (replica)    :5432     │      │
  │  │   ├── Service: n8n-db-rw    :5432     │      │
  │  │   ├── Service: n8n-db-ro    :5432     │      │
  │  │   ├── PVCs managed by CNPG (Longhorn) │      │
  │  │   └── Secret: n8n-db-app (auto-gen)   │      │
  │  └────────────────────────────────────────┘      │
  └──────────────────────────────────────────────────┘
```

---

## Success Criteria

- [ ] `kubectl get pods -n cloudnative-pg` shows the operator pod `Running`
- [ ] `kubectl get crds | grep cnpg` shows Cluster, Backup, ScheduledBackup, Pooler CRDs
- [ ] The `cloudnative-pg` Application is `Synced` and `Healthy` in ArgoCD
- [ ] Operator logs show no errors (`kubectl logs -n cloudnative-pg deploy/cloudnative-pg`)

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `infrastructure/sealed-secrets/` | Reference for simple Helm chart wrapper pattern |
| `docs/specs/n8n.md` | First workload that depends on this operator |
| https://cloudnative-pg.io/documentation/ | Official CNPG documentation |
| https://cloudnative-pg.io/charts/ | Official Helm chart repository |

---

## Design Decisions

### Decision: CloudNativePG over plain PostgreSQL Deployments

**Options considered:**
- Plain PostgreSQL Deployment + PVC + Service + Secret per workload
- CloudNativePG operator with Cluster CRs

**Decision:** CloudNativePG. The operator manages the entire PostgreSQL lifecycle declaratively: PVC provisioning, credential generation, streaming replication, automatic failover, and health monitoring. A single `Cluster` CR replaces 4-5 hand-managed manifests per database.

**Trade-offs:** Requires a cluster-wide operator installation. Worth it for reduced manifest complexity and built-in HA.

### Decision: High availability with 2 instances

**Options considered:**
- 1 instance (no HA, simplest)
- 2 instances (primary + 1 replica, automatic failover)
- 3 instances (primary + 2 replicas, strongest HA)

**Decision:** 2 instances per Cluster CR. On a 3-node k3s cluster, a primary + 1 streaming replica provides automatic failover if a node goes down. 3 instances would consume a Postgres pod on every node, which is excessive for homelab workloads.

**Trade-offs:** Uses more resources than a single instance. Acceptable for reliable database availability.

### Decision: Longhorn storage over Synology CSI

**Options considered:**
- Longhorn (block storage, replicated across nodes)
- Synology CSI (NFS from NAS, large capacity)

**Decision:** Longhorn. Database workloads need low-latency block storage with good IOPS. Longhorn replicates data across nodes, complementing CNPG's application-level replication. Synology NFS adds latency and makes the NAS a single point of failure for databases.

**Trade-offs:** Less total capacity than Synology, but databases are small. Synology remains the right choice for bulk media storage.

### Decision: Operator monitoring enabled

**Options considered:**
- No monitoring (minimal install)
- Enable Prometheus metrics on the operator

**Decision:** Enable monitoring. The CNPG operator exposes Prometheus metrics for cluster health, replication lag, connection counts, etc. Since kube-prometheus-stack is already deployed, this is free visibility.

**Trade-offs:** None meaningful.
