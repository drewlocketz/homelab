# homelab

GitOps repository for a self-hosted k3s homelab cluster managed by ArgoCD.
All cluster state is declared here — infrastructure, workloads, and configuration
are driven from this repo. No manual `kubectl apply` after initial bootstrap.

---

## Cluster

| | |
|---|---|
| **Distribution** | k3s (3-node HA, embedded etcd) |
| **Nodes** | 10.0.4.26, 10.0.4.35, 10.0.4.21 |
| **GitOps** | ArgoCD (app-of-apps pattern) |
| **Secrets** | Sealed Secrets |
| **Ingress** | Traefik |
| **Storage** | Longhorn (app data) + Synology CSI (media) |
| **Provisioning** | Ansible via k3s-io/k3s-ansible |

---

## Repository Structure

```
homelab/
├── bootstrap/               # One-time cluster provisioning
│   ├── k3s-ansible/         # Submodule: k3s-io/k3s-ansible
│   ├── inventory.yml        # Node inventory (3 nodes)
│   └── group_vars/all.yml   # k3s config (no Traefik, embedded etcd)
├── clusters/
│   └── home/
│       ├── root-app.yaml             # Applied once to bootstrap ArgoCD
│       ├── infrastructure-app.yaml   # App-of-apps: infra tier
│       └── workloads-app.yaml        # App-of-apps: workloads tier
├── infrastructure/          # Manifests for cluster-critical components
│   ├── sealed-secrets/
│   ├── longhorn/
│   ├── synology-csi/
│   ├── traefik/
│   ├── cert-manager/
│   └── monitoring/          # kube-prometheus-stack + Loki
├── workloads/               # Manifests for user-facing applications
│   ├── jellyfin/
│   ├── jellyseerr/
│   ├── sonarr/
│   ├── radarr/
│   ├── prowlarr/
│   ├── bazarr/
│   └── sabnzbd/             # Includes gluetun VPN sidecar
├── docs/
│   ├── spec_driven_development.md
│   └── specs/               # Per-feature design specs
└── scripts/                 # Helper scripts
```

---

## How It Works

```
  Git push to main
        │
        ▼
  ┌─────────────┐     watches      ┌─────────────────┐
  │  This Repo  │ ──────────────── │     ArgoCD       │
  │  (GitOps)   │                  │   (in cluster)   │
  └─────────────┘                  └────────┬────────┘
                                            │ syncs
                              ┌─────────────┼─────────────┐
                              ▼             ▼             ▼
                         infrastructure  workloads     config
```

ArgoCD runs inside the cluster and watches this repo. Changes merged to `main`
are automatically reconciled. The app-of-apps pattern means ArgoCD manages
its own application definitions — infrastructure and workloads are deployed
in dependency order via sync waves.

### Sync Wave Order

| Wave | Components |
|---|---|
| 1 | sealed-secrets |
| 2 | longhorn, synology-csi |
| 3 | traefik, cert-manager |
| 4 | monitoring (kube-prom, loki) |
| 5 | jellyfin, jellyseerr, prowlarr |
| 6 | sonarr, radarr, bazarr, sabnzbd |

---

## Getting Started

### 1. Provision the cluster

```bash
cd bootstrap/k3s-ansible
ansible-playbook site.yml -i ../inventory.yml
```

### 2. Bootstrap ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 3. Apply the root app

```bash
kubectl apply -f clusters/home/root-app.yaml
```

ArgoCD will take it from there.

---

## Workloads

### Media Stack

| App | Purpose |
|---|---|
| Jellyfin | Media server (primary) |
| Jellyseerr | Media request management |
| Sonarr | TV show management |
| Radarr | Movie management |
| Prowlarr | Indexer management |
| Bazarr | Subtitle management |
| sabnzbd | Usenet downloader (VPN via gluetun sidecar) |

### Infrastructure

| Component | Purpose |
|---|---|
| Sealed Secrets | Encrypted secrets safe to commit to Git |
| Longhorn | Replicated SSD storage for app data and metadata |
| Synology CSI | NAS storage for large media files |
| Traefik | Ingress controller |
| cert-manager | TLS certificate management |
| kube-prometheus-stack | Metrics and alerting |
| Loki | Log aggregation |

---

## Conventions

- All Kubernetes manifests are YAML
- Secrets are **never** committed in plaintext — encrypt with Sealed Secrets first
- Every non-trivial change should have a spec in `docs/specs/` before implementation
- See `docs/spec_driven_development.md` for how to write specs
