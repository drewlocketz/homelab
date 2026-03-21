# CrowdSec Intrusion Prevention

## Executive Summary

Deploy CrowdSec as the intrusion prevention system for the homelab, replacing the need for fail2ban. CrowdSec is a modern, collaborative security engine that detects malicious behavior by parsing Traefik access logs and blocks bad actors at the ingress level via a Traefik bouncer plugin. Its crowd-sourced threat intelligence means IPs flagged by other CrowdSec users are proactively blocked before they reach this cluster.

**Author:** Drew Locketz
**Date:** 2026-03-20
**Status:** Draft

---

## Dependencies

This spec cannot be implemented until the following specs are complete:

| Spec | Why |
|---|---|
| `traefik.md` | CrowdSec agent parses Traefik logs; bouncer runs as Traefik middleware |
| `longhorn.md` | LAPI persistent storage for decisions DB |
| `cert-manager.md` | TLS for ingress (if dashboard exposed) |

---

## Components

```
                        Internet
                           │
                           ▼
  ┌──────────────────────────────────────────────────────────┐
  │  Traefik (namespace: traefik)                            │
  │  ┌────────────────────────────────────────────────────┐  │
  │  │  CrowdSec Bouncer Plugin (middleware)              │  │
  │  │  ┌──────────────┐    ┌─────────────────────────┐   │  │
  │  │  │ Check IP vs  │───>│ Allow or Block (403)    │   │  │
  │  │  │ decision cache│   └─────────────────────────┘   │  │
  │  │  └──────┬───────┘                                  │  │
  │  │         │ streams decisions                        │  │
  │  └─────────┼──────────────────────────────────────────┘  │
  └────────────┼─────────────────────────────────────────────┘
               │
  ┌────────────┼─────────────────────────────────────────────┐
  │  CrowdSec (namespace: crowdsec)                          │
  │            │                                             │
  │  ┌────────▼────────┐       ┌──────────────────────┐      │
  │  │   LAPI Server   │<──────│   Agent (DaemonSet)  │      │
  │  │   (Deployment)  │       │   Reads Traefik logs │      │
  │  │   Decisions DB  │       └──────────────────────┘      │
  │  │   (Longhorn PVC)│                                     │
  │  └────────┬────────┘                                     │
  │           │                                              │
  │           ▼                                              │
  │  ┌─────────────────┐                                     │
  │  │ CrowdSec Console│  (crowd-sourced blocklists)         │
  │  │ (app.crowdsec.net)                                    │
  │  └─────────────────┘                                     │
  └──────────────────────────────────────────────────────────┘
```

---

## Tasks

- [x] 1. Set Traefik `externalTrafficPolicy: Local` so CrowdSec sees real client IPs
- [x] 2. Enable the CrowdSec bouncer plugin in Traefik Helm values
- [x] 3. Create `infrastructure/crowdsec/` with Helm chart definition
- [x] 4. Create CrowdSec Helm values configuring LAPI, agent, and Traefik log acquisition
- [ ] 5. Create Traefik `Middleware` CRD for the CrowdSec bouncer
- [ ] 6. Apply bouncer middleware to `websecure` entrypoint globally
- [ ] 7. Commit, sync, and verify CrowdSec pods are running
- [ ] 8. Verify an IP ban works end-to-end

> Agents: check off each task as it is completed.

---

## Human Instructions

These steps must be completed after deployment.

**1. Enroll in CrowdSec Console (optional but recommended)**
- Create a free account at https://app.crowdsec.net
- Get an enrollment key from the console
- Run: `kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli console enroll <key>`
- This enables crowd-sourced blocklists and a web dashboard for viewing decisions

**2. Generate bouncer API key**
- Run: `kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli bouncers add traefik-bouncer`
- Save the key and create a sealed secret for it
- Update the Middleware and CrowdSec values to reference the secret

**3. Test the setup**
- Check decisions: `kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli decisions list`
- Manually ban a test IP: `kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli decisions add --ip <test-ip> --duration 1m --reason "test"`
- Verify it returns 403 from that IP

---

## Implementation Details

### Traefik Changes (`infrastructure/traefik/values.yaml`)

Add `externalTrafficPolicy: Local` and enable the CrowdSec bouncer plugin:

```yaml
traefik:
  service:
    spec:
      externalTrafficPolicy: Local

  experimental:
    plugins:
      crowdsec-bouncer:
        moduleName: "github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin"
        version: "v1.4.5"
```

### CrowdSec Helm Chart (`infrastructure/crowdsec/`)

```yaml
# Chart.yaml
apiVersion: v2
name: crowdsec
version: 1.0.0
dependencies:
  - name: crowdsec
    version: "0.20.0"
    repository: https://crowdsecurity.github.io/helm-charts
```

### CrowdSec Helm Values (key settings)

```yaml
crowdsec:
  container_runtime: containerd

  lapi:
    replicas: 1
    persistentVolume:
      data:
        enabled: true
        storageClassName: longhorn
        size: 1Gi

  agent:
    acquisition:
      - namespace: traefik
        podName: traefik-*
        program: traefik
    env:
      - name: COLLECTIONS
        value: "crowdsecurity/traefik"
      - name: PARSERS
        value: "crowdsecurity/cri-logs"
```

### Bouncer Middleware (`infrastructure/crowdsec/middleware.yaml`)

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: crowdsec-bouncer
  namespace: crowdsec
spec:
  plugin:
    crowdsec-bouncer:
      enabled: true
      crowdsecMode: stream
      crowdsecLapiHost: crowdsec-service.crowdsec.svc.cluster.local:8080
      crowdsecLapiKey: "<bouncer-key-from-sealed-secret>"
      crowdsecLapiScheme: http
      forwardedHeadersTrustedIps:
        - "10.42.0.0/16"
```

### Global Middleware Application

Add to Traefik values to apply the bouncer to all websecure traffic:

```yaml
traefik:
  additionalArguments:
    - "--entrypoints.websecure.http.middlewares=crowdsec-crowdsec-bouncer@kubernetescrd"
```

---

## Success Criteria

- [ ] Traefik service has `externalTrafficPolicy: Local`
- [ ] CrowdSec LAPI pod is `Running` in the `crowdsec` namespace
- [ ] CrowdSec agent DaemonSet pods are `Running` on all nodes
- [ ] Agent is parsing Traefik access logs (`cscli metrics` shows parsed lines)
- [ ] Bouncer middleware is active on the `websecure` entrypoint
- [ ] A manually banned IP receives a 403 response
- [ ] Legitimate traffic passes through unaffected

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `infrastructure/traefik/values.yaml` | Current Traefik Helm values — must be modified |
| `infrastructure/traefik/Chart.yaml` | Traefik chart definition |
| `docs/specs/traefik.md` | Traefik deployment spec |
| https://docs.crowdsec.net/u/getting_started/installation/kubernetes/ | Official k8s installation guide |
| https://docs.crowdsec.net/u/bouncers/traefik/ | Traefik bouncer documentation |
| https://github.com/crowdsecurity/helm-charts | CrowdSec Helm charts |
| https://github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin | Traefik bouncer plugin |
| https://lachlanlife.net/posts/2023-03-04-k3s-crowdsec/ | k3s-specific CrowdSec deployment guide |

---

## Design Decisions

### Decision: CrowdSec over fail2ban

**Options considered:**
- fail2ban — traditional, log-parsing, firewall-based banning
- CrowdSec — modern, crowd-sourced, plugin-based

**Decision:** CrowdSec. It integrates natively with Traefik as a middleware plugin (no iptables needed in containers), provides crowd-sourced threat intelligence, and is designed for containerized environments. fail2ban requires host-level iptables access which is awkward in Kubernetes.

**Trade-offs:** CrowdSec has more moving parts (LAPI + agent + plugin). Acceptable given the security benefits.

### Decision: Traefik plugin bouncer (not firewall bouncer)

**Options considered:**
- Firewall bouncer — blocks at iptables/nftables level
- Traefik plugin bouncer — blocks at ingress middleware level

**Decision:** Traefik plugin. It runs inside Traefik itself, no host access needed, no DaemonSet for the bouncer. Simpler for Kubernetes and blocks traffic before it reaches any workload.

**Trade-offs:** Only protects HTTP/HTTPS traffic through Traefik. Non-HTTP services would need a separate bouncer. Acceptable since all external traffic enters through Traefik.

### Decision: externalTrafficPolicy: Local

**Options considered:**
- `Cluster` (current default) — kube-proxy NATs all traffic, CrowdSec sees node IPs
- `Local` — preserves real client IPs, required for CrowdSec to work

**Decision:** `Local`. Without it, CrowdSec would only see internal node/pod IPs and could never ban an actual attacker.

**Trade-offs:** Traffic can only route to nodes running a Traefik pod. Since Traefik runs as a Deployment (1 replica), this means all external traffic goes to one node. This is fine for a homelab but would need a DaemonSet or topology-aware routing in production.

### Decision: Helm chart (not plain manifests)

**Options considered:**
- Plain manifests
- Helm chart wrapper (like Traefik)

**Decision:** Helm chart wrapper. CrowdSec has many components (LAPI, agent DaemonSet, RBAC, services) and the official Helm chart handles all of this. Consistent with how Traefik is deployed in `infrastructure/`.

**Trade-offs:** Adds Helm dependency. Acceptable — already used for Traefik, cert-manager, etc.
