# Blocky — Network-Wide DNS Server

## Executive Summary

Deploy Blocky as the network-wide DNS server for the homelab. Blocky provides DNS-level ad and tracker blocking, local DNS rewrites (so `*.home.drewdevlab.com` resolves to the Traefik LB IP `10.0.4.240` on the LAN without hairpinning through the internet), and Prometheus metrics for monitoring via Grafana. It replaces the router's default DNS and serves as the primary resolver for all devices on the network. Blocky is stateless and config-file-driven, allowing multiple replicas for high availability.

**Author:** Drew Locketz
**Date:** 2026-03-21
**Status:** Draft

---

## Dependencies

This spec cannot be implemented until the following specs are complete:

| Spec | Why |
|---|---|
| `metallb.md` | LoadBalancer IP for the DNS service |
| `monitoring.md` | Prometheus + Grafana for Blocky metrics and dashboards |

---

## Components

```
  LAN Devices (phones, laptops, TVs, etc.)
  ┌──────────────────────────────────────────────────────┐
  │  DNS queries → 10.0.4.241 (Blocky LB IP)            │
  │  e.g. jellyfin.home.drewdevlab.com → 10.0.4.240     │
  │  e.g. ads.tracker.com → 0.0.0.0 (blocked)           │
  └──────────────────────┬───────────────────────────────┘
                         │
  k3s Cluster            ▼
  ┌──────────────────────────────────────────────────────┐
  │                                                      │
  │  namespace: blocky                                   │
  │  ┌────────────────────────────────────────────────┐  │
  │  │  Blocky (Deployment, 2 replicas)              │  │
  │  │  ├── DNS: :53 (UDP+TCP) via LoadBalancer       │  │
  │  │  ├── Metrics: :4000 via Prometheus scrape      │  │
  │  │  └── Config: ConfigMap (stateless)             │  │
  │  └────────────────────────────────────────────────┘  │
  │                                                      │
  │  Anti-affinity: replicas scheduled on different nodes │
  │                                                      │
  │  DNS Rewrites:                                       │
  │  *.home.drewdevlab.com → 10.0.4.240 (Traefik)      │
  │                                                      │
  │  Upstream DNS:                                       │
  │  → 1.1.1.1 (Cloudflare)                             │
  │  → 1.0.0.1 (Cloudflare secondary)                   │
  └──────────────────────────────────────────────────────┘

  Router DHCP
  ┌──────────────────────────────────────────────────────┐
  │  Primary DNS: 10.0.4.241 (Blocky LB IP)             │
  │  Fallback DNS: 1.1.1.1 (Cloudflare)                 │
  │  (all DHCP clients get both DNS servers)             │
  └──────────────────────────────────────────────────────┘
```

---

## Tasks

- [x] 1. Create `workloads/blocky/` directory
- [x] 2. Create `configmap.yaml` — Blocky configuration (upstream DNS, blocking lists, custom DNS rewrites)
- [x] 3. Create `deployment.yaml` — `spx01/blocky:latest`, 2 replicas, pod anti-affinity, config from ConfigMap
- [x] 4. Create `service-dns.yaml` — LoadBalancer on port 53 (UDP+TCP) with MetalLB IP annotation
- [x] 5. Create `service-metrics.yaml` — ClusterIP on port 4000 (Prometheus metrics)
- [x] 6. ~~Create ArgoCD Application~~ — Not needed; `workloads-appset.yaml` auto-discovers `workloads/*`
- [ ] 7. Commit, sync, and verify pods are running on separate nodes
- [ ] 8. Verify DNS resolution and ad blocking work
- [ ] 9. Import Blocky Grafana dashboard
- [ ] 10. Update router DHCP to use Blocky as primary DNS with Cloudflare fallback

> Agents: check off each task as it is completed.

---

## Human Instructions

These steps must be completed after deployment.

**1. Choose a MetalLB IP for the DNS LoadBalancer**
- Pick an unused IP from the MetalLB pool for the DNS service (e.g. `10.0.4.241`)
- This IP will be the DNS server address for all network devices

**2. Verify DNS resolution**
- `dig @10.0.4.241 google.com` — should resolve (upstream forwarding)
- `dig @10.0.4.241 jellyfin.home.drewdevlab.com` — should return `10.0.4.240`
- `dig @10.0.4.241 ads.google.com` — should return `0.0.0.0` (blocked)

**3. Import Grafana dashboard**
- Import the Blocky Grafana dashboard (ID `13768`) or use the one from the Blocky docs
- Verify metrics are flowing in Grafana

**4. Update router DHCP**
- Set primary DNS to `10.0.4.241` (Blocky)
- Set secondary/fallback DNS to `1.1.1.1` (Cloudflare)
- The fallback ensures internet keeps working if the cluster is down
- All devices will pick up the new DNS on their next DHCP lease renewal

---

## Implementation Details

### ConfigMap (`workloads/blocky/configmap.yaml`)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: blocky-config
  labels:
    app: blocky
data:
  config.yml: |
    upstreams:
      groups:
        default:
          - 1.1.1.1
          - 1.0.0.1

    blocking:
      denylists:
        ads:
          - https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
          - |
            /^ad([sxv]?[0-9]*|system)[_.-]([^.[:space:]]+\.){1,}|[_.-]ad([sxv]?[0-9]*|system)[_.-]/
          - https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt
          - https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt
      clientGroupsBlock:
        default:
          - ads

    customDNS:
      mapping:
        "*.home.drewdevlab.com": 10.0.4.240

    ports:
      dns: 53
      http: 4000

    prometheus:
      enable: true
      path: /metrics

    log:
      level: info
```

### Deployment (`workloads/blocky/deployment.yaml`)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: blocky
  labels:
    app: blocky
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 0
  selector:
    matchLabels:
      app: blocky
  template:
    metadata:
      labels:
        app: blocky
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                  - key: app
                    operator: In
                    values:
                      - blocky
              topologyKey: kubernetes.io/hostname
      containers:
        - name: blocky
          image: spx01/blocky:latest
          ports:
            - containerPort: 53
              name: dns-tcp
              protocol: TCP
            - containerPort: 53
              name: dns-udp
              protocol: UDP
            - containerPort: 4000
              name: metrics
          volumeMounts:
            - name: config
              mountPath: /app/config.yml
              subPath: config.yml
              readOnly: true
          resources:
            requests:
              memory: 64Mi
              cpu: 50m
            limits:
              memory: 128Mi
      volumes:
        - name: config
          configMap:
            name: blocky-config
```

### DNS Service (`workloads/blocky/service-dns.yaml`)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: blocky-dns
  labels:
    app: blocky
  annotations:
    metallb.universe.tf/loadBalancerIPs: "10.0.4.241"
spec:
  type: LoadBalancer
  selector:
    app: blocky
  ports:
    - port: 53
      targetPort: dns-tcp
      protocol: TCP
      name: dns-tcp
    - port: 53
      targetPort: dns-udp
      protocol: UDP
      name: dns-udp
```

### Metrics Service (`workloads/blocky/service-metrics.yaml`)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: blocky-metrics
  labels:
    app: blocky
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "4000"
spec:
  type: ClusterIP
  selector:
    app: blocky
  ports:
    - port: 4000
      targetPort: metrics
      protocol: TCP
      name: metrics
```

---

## Success Criteria

- [ ] Two Blocky pods are `Running` in the `blocky` namespace, scheduled on different nodes
- [ ] `dig @10.0.4.241 jellyfin.home.drewdevlab.com` returns `10.0.4.240`
- [ ] `dig @10.0.4.241 google.com` resolves (upstream forwarding works)
- [ ] Ad domains are blocked (e.g. `dig @10.0.4.241 ads.google.com` returns `0.0.0.0`)
- [ ] Prometheus is scraping Blocky metrics on port 4000
- [ ] Grafana dashboard shows DNS query metrics
- [ ] Killing one Blocky pod does not interrupt DNS resolution
- [ ] All LAN devices use Blocky as their DNS server via DHCP
- [ ] Router DHCP has `1.1.1.1` as fallback DNS

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `infrastructure/traefik/values.yaml` | Traefik Helm values — MetalLB IP `10.0.4.240` |
| `infrastructure/monitoring/values.yaml` | Prometheus + Grafana stack |
| `docs/specs/ddclient.md` | Dynamic DNS for external resolution of `*.home.drewdevlab.com` |
| `docs/specs/traefik.md` | Traefik ingress — handles HTTPS routing |
| `workloads/prowlarr/` | Reference for plain-manifest workload pattern |
| https://0xerr0r.github.io/blocky/ | Official Blocky documentation |
| https://github.com/0xERR0R/blocky | Blocky GitHub repository |

---

## Design Decisions

### Decision: Blocky over AdGuard Home

**Options considered:**
- AdGuard Home — modern UI, DNS rewrites, ad blocking, but single-instance with stateful config
- Pi-hole — classic, large community, but poor Kubernetes multi-replica support
- Blocky — stateless, YAML-config, native multi-replica, Prometheus metrics, no web UI
- CoreDNS with block plugin — possible but ad blocking is DIY

**Decision:** Blocky. Its stateless, config-file-driven design means multiple replicas work out of the box with no shared state or leader election. Config lives in a ConfigMap, so it's fully GitOps-friendly. Built-in Prometheus metrics integrate with the existing monitoring stack.

**Trade-offs:** No built-in web UI for browsing query logs. Mitigated by Grafana dashboards using Blocky's Prometheus metrics, which actually provides better visualization than a standalone UI.

### Decision: Two replicas with pod anti-affinity

**Options considered:**
- Single replica (simpler, but single point of failure)
- Two replicas with anti-affinity (HA, survives single node failure)
- DaemonSet (replica on every node, overkill for DNS)

**Decision:** Two replicas with `requiredDuringSchedulingIgnoredDuringExecution` anti-affinity on `kubernetes.io/hostname`. Ensures DNS survives a single node failure or reboot. MetalLB load-balances across both pods.

**Trade-offs:** Requires at least two schedulable nodes. Acceptable for this cluster.

### Decision: RollingUpdate strategy

**Options considered:**
- Recreate — brief DNS downtime during updates
- RollingUpdate with maxUnavailable: 1 — always at least one pod serving DNS

**Decision:** RollingUpdate with `maxUnavailable: 1`, `maxSurge: 0`. During config or image updates, one pod stays running while the other is replaced. No DNS downtime during rollouts.

**Trade-offs:** Brief period with only one replica during updates. Acceptable.

### Decision: No externalTrafficPolicy: Local

**Options considered:**
- `Local` — preserves client IP but only routes to nodes with a Blocky pod
- `Cluster` — kube-proxy distributes across all nodes, loses client IP

**Decision:** `Cluster` (default). With two replicas and anti-affinity, traffic can reach either pod regardless of which node the MetalLB VIP lands on. Client IP preservation is less important for Blocky since it doesn't have a query log UI — metrics are aggregated in Prometheus.

**Trade-offs:** Lose per-client-IP visibility in metrics. If per-device stats are needed later, can switch to `Local` since anti-affinity ensures pods are on different nodes.

### Decision: Fallback DNS on router

**Options considered:**
- Blocky as sole DNS (all DNS fails if cluster is down)
- Blocky as primary with Cloudflare `1.1.1.1` as fallback

**Decision:** Fallback DNS. Router DHCP hands out both `10.0.4.241` and `1.1.1.1`. If the cluster is completely down, devices fall back to Cloudflare. Internet keeps working, only local `*.home.drewdevlab.com` names and ad blocking are lost.

**Trade-offs:** When falling back, ads are not blocked and local names don't resolve. Acceptable — internet working is the priority.

### Decision: Dedicated MetalLB IP for DNS

**Options considered:**
- Share Traefik's IP (`10.0.4.240`) and use different ports
- Assign a separate MetalLB IP for DNS (e.g. `10.0.4.241`)

**Decision:** Separate IP. DNS must be on port 53, which doesn't conflict with Traefik's 80/443, but a dedicated IP is cleaner and easier to configure in router DHCP settings. MetalLB IPs are free.

**Trade-offs:** Uses one more IP from the MetalLB pool. Negligible cost.
