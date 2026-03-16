# k3s Cluster Bootstrap via Ansible

## Executive Summary

Ansible is an agentless IT automation tool that allows infrastructure to be provisioned
in a repeatable, idempotent way using declarative YAML playbooks. Rather than manually
SSHing into each node to install and configure k3s, Ansible lets us define the desired
state once and apply it consistently across all nodes. This spec covers adding the official
`k3s-io/k3s-ansible` playbook as a git submodule and configuring it to provision a
3-node HA k3s cluster with embedded etcd. Traefik ingress will be disabled at install
time so it can be managed via ArgoCD later.

**Author:** Drew Locketz
**Date:** 2026-03-15
**Status:** In Progress

---

## Tasks

- [x] 1. Add `k3s-io/k3s-ansible` as a git submodule under `bootstrap/k3s-ansible`
- [x] 2. Create `bootstrap/inventory.yml` with the 3 node IPs
- [x] 3. Configure k3s settings in `bootstrap/inventory.yml` (disable Traefik, enable embedded etcd via `server_config_yaml`)
- [x] 4. Verify SSH access from the control machine to all 3 nodes
- [x] 5. Run the Ansible playbook to provision the cluster
- [x] 6. Verify all nodes are Ready via `kubectl get nodes`
- [x] 7. Verify embedded etcd is healthy (built into k3s-server process, confirmed via node roles showing `etcd`)
- [x] 8. Verify Traefik is absent from the cluster
- [ ] 9. Verify HA by cordoning one node and confirming the cluster remains operational

---

## Components

```
  Control Machine (you)
  ┌──────────────────────────────────────┐
  │  ansible-playbook site.yml           │
  │  bootstrap/                          │
  │  ├── k3s-ansible/  (submodule)       │
  │  ├── inventory.yml                   │
  │  └── group_vars/all.yml              │
  └──────────┬───────────────────────────┘
             │ SSH
     ┌───────┼───────┐
     ▼       ▼       ▼
  ┌──────┐ ┌──────┐ ┌──────┐
  │ k3s  │ │ k3s  │ │ k3s  │
  │server│ │server│ │server│
  │+etcd │ │+etcd │ │+etcd │
  │      │ │      │ │      │
  │.4.26 │ │.4.35 │ │.4.21 │
  └──────┘ └──────┘ └──────┘
      └────────┬───────┘
               │ embedded etcd
               │ (HA control plane)
        ┌──────▼──────┐
        │  Kubernetes │
        │  API Server │
        └─────────────┘
```

All 3 nodes act as both server (control plane + etcd) and worker nodes.
No external database is required — etcd is embedded and distributed across all 3 nodes.

---

## Success Criteria

- [ ] All 3 nodes appear as `Ready` in `kubectl get nodes`
- [ ] All nodes show role `control-plane` confirming HA server configuration
- [ ] Embedded etcd pods are present and healthy in `kube-system`
- [ ] Traefik is **not** present in the cluster (`kubectl get all -n kube-system | grep traefik` returns nothing)
- [ ] Cluster remains operational when one node is cordoned/taken offline (HA verified)
- [ ] `kubectl get nodes` is accessible from the control machine via the generated kubeconfig

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| https://github.com/k3s-io/k3s-ansible | Official k3s Ansible playbook used as submodule |
| https://github.com/timothystewart6/k3s-ansible | Alternative fork evaluated during design — rejected (see Design Decisions) |

---

## Design Decisions

### Decision: Official k3s-io/k3s-ansible over timothystewart6/k3s-ansible

**Options considered:**
- `timothystewart6/k3s-ansible` — community fork, ~3k stars, bundles kube-vip and MetalLB out of the box
- `k3s-io/k3s-ansible` — official repo maintained by the k3s org, updated March 11 2026, ~2.7k stars, vanilla k3s install

**Decision:** Chose the official `k3s-io/k3s-ansible` because it is maintained by the k3s organization and focuses on a clean k3s install without opinionated extras.

**Trade-offs:** kube-vip and MetalLB are not included and will need to be added separately via ArgoCD. This is intentional — keeping Ansible responsible only for OS-level k3s provisioning and letting ArgoCD manage everything running inside the cluster.

---

### Decision: Disable Traefik at install time

**Options considered:**
- Allow Traefik to install (k3s default) and replace it later
- Disable Traefik at install time via `--disable traefik` flag

**Decision:** Disable at install time to avoid a conflicting Traefik installation that would need to be cleaned up before deploying a GitOps-managed ingress controller.

**Trade-offs:** No ingress will be available until one is deployed via ArgoCD after bootstrap.
