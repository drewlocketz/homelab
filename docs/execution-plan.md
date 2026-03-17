# Execution Plan

This document defines the order in which specs should be implemented, based on
dependencies between components. Steps within a phase are independent of each other
and can be done in parallel.

---

## Completed

| Spec | Notes |
|---|---|
| `k3s-ansible-bootstrap` | 3-node HA k3s cluster provisioned |
| `argocd-bootstrap` | ArgoCD installed, SSH repo access configured |
| `app-of-apps-structure` | ApplicationSets deployed, sealed-secrets stub live |

---

## Phase 1 — Security

No dependencies beyond the completed bootstrap. Do these before anything that
requires secrets or commits sensitive values to the repo.

```
[ ansible-vault-inventory ]   [ sealed-secrets ]
        │                            │
        │  Encrypts k3s token        │  Enables SealedSecrets for
        │  in inventory.yml          │  all future secret management
        ▼                            ▼
   Repo is safe              Secrets foundation
   for version control       is in place
```

| Order | Spec | Why |
|---|---|---|
| 1a | `ansible-vault-inventory` | Encrypts the plaintext k3s token in `bootstrap/inventory.yml` — do this before pushing the repo anywhere |
| 1b | `sealed-secrets` | Required by synology-csi, cert-manager, and monitoring for credential management |

---

## Phase 2 — Storage

Longhorn has no secret dependencies. Start it as soon as Phase 1 is done.
Synology CSI requires sealed-secrets and the NAS to be physically set up.

```
     [ longhorn ]          [ synology-csi ]
          │                      │
          │  Local SSD storage   │  NAS-backed NFS storage
          │  for app config      │  for media + downloads
          │  and databases       │  (needs sealed-secrets
          ▼                      │   + NAS setup first)
   App storage ready             ▼
                        Media storage ready
```

| Order | Spec | Why |
|---|---|---|
| 2a | `longhorn` | No secret dependencies; installs node packages via Ansible and deploys storage backend for app data |
| 2b | `synology-csi` | Depends on sealed-secrets (1b) for NAS credentials; also requires NAS to be physically configured per Human Instructions in spec |

---

## Phase 3 — Networking

MetalLB has no secret dependencies. cert-manager needs sealed-secrets for the
Cloudflare API token. Traefik needs both MetalLB (for its IP) and cert-manager
(for TLS) before it is fully functional.

```
  [ metallb ]        [ cert-manager ]
      │                     │
      │  Assigns            │  Issues wildcard TLS cert
      │  10.0.4.240         │  via Cloudflare DNS-01
      │  to Traefik         │  (needs sealed-secrets)
      └──────────┬──────────┘
                 ▼
           [ traefik ]
                 │
                 │  Ingress controller
                 │  HTTP→HTTPS redirect
                 │  Routes by hostname
                 ▼
      *.home.yourdomain.com live
```

| Order | Spec | Why |
|---|---|---|
| 3a | `metallb` | No dependencies; provides LoadBalancer IPs to the cluster |
| 3b | `cert-manager` | Depends on sealed-secrets (1b) for Cloudflare API token; can deploy in parallel with metallb |
| 3c | `traefik` | Depends on metallb (3a) for IP assignment and cert-manager (3b) for TLS — do this last in the phase |

---

## Phase 4 — Observability

Monitoring depends on Longhorn for persistent storage and sealed-secrets for the
Grafana admin password. Networking is not required — Grafana is accessed via
`kubectl port-forward` until an IngressRoute is added post-ingress.

```
  [ longhorn ] + [ sealed-secrets ]
              │
              ▼
         [ monitoring ]
              │
              │  Prometheus (30d retention)
              │  Grafana (persisted dashboards)
              │  Loki + Alloy (log aggregation)
              │  AlertManager
              ▼
      Observability stack live
```

| Order | Spec | Why |
|---|---|---|
| 4a | `monitoring` | Depends on longhorn (2a) for PVCs and sealed-secrets (1b) for Grafana credentials |

---

## Full Dependency Graph

```
  [k3s]──►[argocd]──►[app-of-apps]
                           │
              ┌────────────┼─────────────┐
              ▼            ▼             ▼
   [ansible-vault]  [sealed-secrets]  [metallb]
                           │               │
              ┌────────────┼───────┐       │
              ▼            ▼       ▼       │
         [longhorn]  [synology] [cert-manager]
              │                       │
              │            ┌──────────┘
              │            ▼
              │         [traefik]
              │
              └──►[monitoring]
```

---

## Summary Table

| Phase | Spec | Status | Depends On |
|---|---|---|---|
| ✅ | k3s-ansible-bootstrap | Complete | — |
| ✅ | argocd-bootstrap | Complete | k3s |
| ✅ | app-of-apps-structure | Complete | argocd |
| 1a | ansible-vault-inventory | Draft | app-of-apps |
| 1b | sealed-secrets | Complete | app-of-apps |
| 2a | longhorn | Draft | app-of-apps |
| 2b | synology-csi | Draft | sealed-secrets |
| 3a | metallb | Draft | app-of-apps |
| 3b | cert-manager | Draft | sealed-secrets |
| 3c | traefik | Draft | metallb, cert-manager |
| 4a | monitoring | Draft | longhorn, sealed-secrets |
