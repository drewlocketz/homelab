# Scripts

Helper scripts for managing the homelab cluster. All scripts should be run from the repo root.

---

## run-k3s-ansible.sh

Runs the k3s-ansible playbook inside a Docker container — no local Ansible installation required.

**Prerequisites:**
- Docker installed and running
- SSH key copied to each node (`ssh-copy-id -i ~/.ssh/id_ed25519 <user>@<node-ip>`)
- `bootstrap/inventory.yml` updated with real node IPs and a generated token

**Usage:**

```bash
# Full provisioning run
./scripts/run-k3s-ansible.sh

# Dry run — shows what would change without applying
./scripts/run-k3s-ansible.sh --check

# Run specific tags only
./scripts/run-k3s-ansible.sh --tags prereq

# Use a custom SSH key
SSH_KEY=~/.ssh/homelab ./scripts/run-k3s-ansible.sh
```

**Pre-flight checks performed:**
- Docker is installed and the daemon is running
- `bootstrap/k3s-ansible` submodule is initialised
- `bootstrap/inventory.yml` exists
- Placeholder IPs have been replaced with real node IPs
- Cluster token has been changed from the default `changeme!`
- Any unresolved `TODO` items in the inventory are flagged
- SSH key exists locally
- SSH connectivity to each node is verified before the playbook runs

**Generating a token:**
```bash
openssl rand -base64 64
```
