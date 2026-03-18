# Monitoring — kube-prometheus-stack + Loki

## Executive Summary

This spec covers deploying a full observability stack to the homelab cluster:
kube-prometheus-stack (Prometheus, Grafana, AlertManager, node-exporter,
kube-state-metrics) for metrics and alerting, and Loki + Grafana Alloy for log
aggregation. Both are deployed as a single ArgoCD Application from
`infrastructure/monitoring/` using an umbrella Helm chart. Grafana dashboards and
Prometheus data are persisted to Longhorn. Grafana is accessible within the cluster
only — ingress is covered by a separate spec.

**Author:** Drew Locketz
**Date:** 2026-03-16
**Status:** Complete

---

## Tasks

### Secrets
- [x] 1. Create a SealedSecret for the Grafana admin password in `infrastructure/monitoring/`
- [x] 2. Create a SealedSecret for AlertManager notification credentials in `infrastructure/monitoring/` (once notification channel is decided)

### Deploy
- [x] 3. Create `infrastructure/monitoring/Chart.yaml` declaring kube-prometheus-stack and Loki as dependencies
- [x] 4. Create `infrastructure/monitoring/values.yaml` with Prometheus retention, Longhorn PVCs, Loki datasource, and AlertManager config
- [ ] 5. Verify ArgoCD syncs the `monitoring` Application
- [ ] 6. Verify all pods are `Running` in the `monitoring` namespace

### Validate
- [ ] 7. Verify Prometheus is scraping cluster metrics (`kubectl port-forward` to Prometheus UI)
- [ ] 8. Verify Grafana is accessible via `kubectl port-forward` and dashboards are populated
- [ ] 9. Verify Loki is receiving logs from Alloy
- [ ] 10. Verify AlertManager is running and config is valid
- [ ] 11. Verify Grafana dashboards and data survive a pod restart (Longhorn persistence working)

---

## Components

```
  This repo
  ┌──────────────────────────────────────────────┐
  │  infrastructure/monitoring/                  │
  │  ├── Chart.yaml          (umbrella chart)    │
  │  ├── values.yaml                             │
  │  ├── grafana-secret-sealed.yaml              │
  │  └── alertmanager-secret-sealed.yaml         │
  └──────────────────┬───────────────────────────┘
                     │ ArgoCD syncs
                     ▼
  ┌──────────────────────────────────────────────┐
  │              k3s Cluster                     │
  │                                              │
  │  namespace: monitoring                       │
  │                                              │
  │  ┌─────────────────────────────────────┐     │
  │  │  kube-prometheus-stack              │     │
  │  │  ├── Prometheus   ──── Longhorn PVC │     │
  │  │  ├── Grafana      ──── Longhorn PVC │     │
  │  │  ├── AlertManager                   │     │
  │  │  ├── node-exporter   (DaemonSet)    │     │
  │  │  └── kube-state-metrics             │     │
  │  └─────────────────────────────────────┘     │
  │                                              │
  │  ┌─────────────────────────────────────┐     │
  │  │  Loki (single binary)               │     │
  │  │  └── Longhorn PVC                   │     │
  │  │                                     │     │
  │  │  Grafana Alloy  (DaemonSet)         │     │
  │  │  └── ships logs from all nodes      │     │
  │  │       to Loki                       │     │
  │  └─────────────────────────────────────┘     │
  └──────────────────────────────────────────────┘
```

### Data Flow

```
  Each Node
  ┌─────────────────────────────────┐
  │  node-exporter  ─── metrics ──►─┐
  │  Alloy          ─── logs ─────►─┤
  └─────────────────────────────────┘
                                    │
  kube-state-metrics ── metrics ──►─┤
  kubelet            ── metrics ──►─┤
                                    ▼
                             Prometheus ──► Longhorn PVC
                             Loki       ──► Longhorn PVC
                                    │
                                    ▼
                             Grafana (datasources: Prometheus + Loki)
                             AlertManager
```

---

## Success Criteria

- [ ] All pods `Running` in the `monitoring` namespace
- [ ] Prometheus retains 30 days of metrics
- [ ] Grafana is reachable via `kubectl port-forward` with persisted dashboards
- [ ] Loki datasource is configured in Grafana and logs are queryable
- [ ] AlertManager is running with a valid config
- [ ] Grafana data survives pod restart (Longhorn PVC working)

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `docs/specs/sealed-secrets.md` | Required — Grafana and AlertManager credentials stored as SealedSecrets |
| `docs/specs/longhorn.md` | Required — Longhorn provides persistent storage for Prometheus and Grafana |
| `docs/specs/app-of-apps-structure.md` | ApplicationSet auto-generates the `monitoring` Application from `infrastructure/monitoring/` |
| https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack | kube-prometheus-stack Helm chart |
| https://grafana.com/docs/loki/latest/setup/install/helm/ | Loki Helm chart |
| https://grafana.com/docs/alloy/latest/ | Grafana Alloy (log shipper) |

---

## Design Decisions

### Decision: Umbrella chart for kube-prometheus-stack + Loki

**Options considered:**
- Separate ArgoCD Applications for kube-prometheus-stack and Loki (`infrastructure/kube-prometheus-stack/`, `infrastructure/loki/`)
- Single umbrella chart in `infrastructure/monitoring/`

**Decision:** Single umbrella chart. kube-prometheus-stack and Loki are tightly coupled —
Loki is a Grafana datasource, Alloy ships logs to Loki, and all components share the
`monitoring` namespace. Managing them as one ArgoCD Application simplifies datasource
wiring and keeps monitoring concerns together.

**Trade-offs:** Less granular ArgoCD sync control. If one chart has an issue, the whole
monitoring Application is affected. Acceptable for a homelab.

---

### Decision: Grafana Alloy over Promtail

**Options considered:**
- Promtail — the traditional Loki log shipper, widely documented
- Grafana Alloy — the current recommended log shipper, replaces Promtail

**Decision:** Grafana Alloy. Promtail is in maintenance mode and Grafana Alloy is its
officially recommended replacement. Alloy is more capable (supports metrics, logs, and
traces) and is the direction the Grafana ecosystem is moving.

**Trade-offs:** Less community documentation compared to Promtail. Alloy's config syntax
(River/Alloy syntax) is less familiar than Promtail's YAML. Worth it to avoid building on
a deprecated tool.

---

### Decision: Loki in single binary (monolithic) mode

**Options considered:**
- Microservices mode — each Loki component runs as a separate deployment
- Single binary mode — all Loki components in one process

**Decision:** Single binary. Microservices mode is designed for large-scale production
deployments and adds significant complexity. Single binary is the recommended mode for
homelab and small clusters.

**Trade-offs:** Cannot scale individual Loki components independently. Not a concern at
homelab scale.

---

### Decision: Longhorn for Prometheus and Grafana persistence, not Loki

**Options considered:**
- Persist all three (Prometheus, Grafana, Loki) to Longhorn
- Persist Prometheus and Grafana only, Loki ephemeral

**Decision:** Persist Prometheus (30 day retention) and Grafana (dashboards and config).
Loki log storage will also use a Longhorn PVC — logs are useful to retain across pod
restarts. All three get Longhorn PVCs.

**Trade-offs:** Three Longhorn PVCs for the monitoring stack. Prometheus will be the
largest consumer given 30 day metric retention.

---

### Decision: No ingress in this spec

**Options considered:**
- Deploy Grafana ingress as part of this spec
- Keep Grafana internal-only, ingress covered by a separate spec

**Decision:** Ingress is a separate spec. Traefik is not yet deployed, so Grafana will
be accessible via `kubectl port-forward` during initial setup. Ingress rules for Grafana
will be added once the ingress spec is implemented.

**Trade-offs:** Grafana is not externally accessible until the ingress spec is done.
Acceptable — port-forwarding is sufficient for initial validation.

---

### Decision: AlertManager notification channels TBD

AlertManager will be deployed with a valid but minimal config initially. Notification
channels (Slack, email, PagerDuty, etc.) should be decided and added as a follow-up
task once the stack is running. Credentials for notification channels will be stored
as a SealedSecret.
