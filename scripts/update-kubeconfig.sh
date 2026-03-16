#!/usr/bin/env bash
# update-kubeconfig.sh
# Fetches the kubeconfig from the first reachable k3s server node and
# installs it to ~/.kube/config with the correct server address.
#
# Usage: ./scripts/update-kubeconfig.sh
#
# Environment variables:
#   SSH_KEY   Path to SSH private key (default: ~/.ssh/id_ed25519)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INVENTORY="$REPO_ROOT/bootstrap/inventory.yml"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.kube/config}"

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; }
header(){ echo -e "\n${BOLD}$*${NC}"; }

header "=== Pre-flight checks ==="

# 1. kubectl installed
if ! command -v kubectl &>/dev/null; then
  error "kubectl is not installed or not in PATH"
  echo ""
  echo "  Install it with:"
  echo "    curl -LO \"https://dl.k8s.io/release/\$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\""
  echo "    chmod +x kubectl && mv kubectl ~/.local/bin/"
  exit 1
fi
info "kubectl found ($(kubectl version --client --short 2>/dev/null || kubectl version --client | head -1))"

# 2. Inventory exists
if [ ! -f "$INVENTORY" ]; then
  error "inventory.yml not found at $INVENTORY"
  exit 1
fi
info "inventory.yml found"

# 3. SSH key exists
if [ ! -f "$SSH_KEY" ]; then
  if [ -f "$HOME/.ssh/id_rsa" ]; then
    SSH_KEY="$HOME/.ssh/id_rsa"
    warn "id_ed25519 not found, falling back to id_rsa"
  else
    error "No SSH key found. Set SSH_KEY=/path/to/key or ensure ~/.ssh/id_ed25519 exists"
    exit 1
  fi
fi
info "SSH key: $SSH_KEY"

# ── Find first reachable server node ─────────────────────────────────────────
ANSIBLE_USER=$(grep 'ansible_user:' "$INVENTORY" | awk '{print $2}' | tr -d '"')
ANSIBLE_PORT=$(grep 'ansible_port:' "$INVENTORY" | awk '{print $2}' | tr -d '"')
PORT="${ANSIBLE_PORT:-22}"
HOSTS=$(grep -E '^\s{8}[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:' "$INVENTORY" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')

header "=== Finding reachable node ==="

TARGET_NODE=""
for host in $HOSTS; do
  if ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no \
         -p "$PORT" -i "$SSH_KEY" "${ANSIBLE_USER}@${host}" "exit 0" 2>/dev/null; then
    info "Reachable: $host — using this node"
    TARGET_NODE="$host"
    break
  else
    warn "$host unreachable, trying next..."
  fi
done

if [ -z "$TARGET_NODE" ]; then
  error "No reachable server nodes found. Check that your nodes are up and SSH is accessible."
  exit 1
fi

# ── Fetch and install kubeconfig ──────────────────────────────────────────────
header "=== Fetching kubeconfig ==="

mkdir -p "$(dirname "$KUBECONFIG_PATH")"

ssh -o StrictHostKeyChecking=no -p "$PORT" -i "$SSH_KEY" \
  "${ANSIBLE_USER}@${TARGET_NODE}" "sudo cat /etc/rancher/k3s/k3s.yaml" \
  | sed "s/127.0.0.1/${TARGET_NODE}/g" \
  > "$KUBECONFIG_PATH"

chmod 600 "$KUBECONFIG_PATH"
info "Kubeconfig written to $KUBECONFIG_PATH (server: https://${TARGET_NODE}:6443)"

# ── Verify ───────────────────────────────────────────────────────────────────
header "=== Verifying cluster access ==="

if kubectl get nodes -o wide; then
  echo ""
  info "Cluster access confirmed"
else
  error "kubectl get nodes failed — kubeconfig may be incorrect"
  exit 1
fi
