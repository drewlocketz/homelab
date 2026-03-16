#!/usr/bin/env bash
# run-k3s-ansible.sh
# Runs the k3s-ansible playbook inside a Docker container.
# Usage: ./scripts/run-k3s-ansible.sh [--check] [--tags <tags>]
#
# Environment variables:
#   SSH_KEY   Path to SSH private key (default: ~/.ssh/id_ed25519)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_DIR="$REPO_ROOT/bootstrap"
INVENTORY="$BOOTSTRAP_DIR/inventory.yml"
K3S_ANSIBLE_DIR="$BOOTSTRAP_DIR/k3s-ansible"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
ANSIBLE_IMAGE="willhallonline/ansible:2.16-alpine-3.20"

# Placeholder IPs — update inventory.yml before running
PLACEHOLDER_IPS=("192.168.1.10" "192.168.1.11" "192.168.1.12")

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; }
header(){ echo -e "\n${BOLD}$*${NC}"; }

# ── Argument parsing ──────────────────────────────────────────────────────────
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --check)      EXTRA_ARGS+=("--check"); shift ;;
    --tags)       EXTRA_ARGS+=("--tags" "$2"); shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# ── Pre-flight checks ─────────────────────────────────────────────────────────
header "=== Pre-flight checks ==="

# 1. Docker installed
if ! command -v docker &>/dev/null; then
  error "Docker not found in PATH — install Docker and try again"
  exit 1
fi
info "Docker found"

# 2. Docker running
if ! docker info &>/dev/null 2>&1; then
  error "Docker daemon is not running"
  exit 1
fi
info "Docker daemon running"

# 3. Submodule initialised
if [ ! -f "$K3S_ANSIBLE_DIR/playbooks/site.yml" ]; then
  error "k3s-ansible submodule is not initialised"
  echo "  Run: git submodule update --init"
  exit 1
fi
info "k3s-ansible submodule initialised"

# 4. Inventory exists
if [ ! -f "$INVENTORY" ]; then
  error "inventory.yml not found at $INVENTORY"
  exit 1
fi
info "inventory.yml found"

# 5. Placeholder IPs not still in use
FOUND_PLACEHOLDER=0
for ip in "${PLACEHOLDER_IPS[@]}"; do
  if grep -q "^        ${ip}:" "$INVENTORY" 2>/dev/null; then
    error "Placeholder IP still present in inventory: $ip"
    FOUND_PLACEHOLDER=1
  fi
done
if [ "$FOUND_PLACEHOLDER" = "1" ]; then
  echo "  Update bootstrap/inventory.yml with your real node IPs before running."
  exit 1
fi
info "Node IPs look real"

# 6. Placeholder token not still in use
if grep -q 'changeme!' "$INVENTORY"; then
  error "inventory.yml still has the placeholder token"
  echo "  Generate one with: openssl rand -base64 64"
  exit 1
fi
info "Cluster token set"

# 7. Any remaining TODOs — warn but allow override
if grep -q 'TODO' "$INVENTORY"; then
  warn "inventory.yml has unresolved TODO items:"
  grep -n 'TODO' "$INVENTORY" | sed 's/^/    /'
  echo ""
  read -rp "  Continue anyway? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
fi

# 8. SSH key exists
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

# 9. SSH connectivity to each node
ANSIBLE_USER=$(grep 'ansible_user:' "$INVENTORY" | awk '{print $2}' | tr -d '"')
ANSIBLE_PORT=$(grep 'ansible_port:' "$INVENTORY" | awk '{print $2}' | tr -d '"')
PORT="${ANSIBLE_PORT:-22}"
HOSTS=$(grep -E '^\s{8}[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:' "$INVENTORY" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')

SSH_FAILED=0
for host in $HOSTS; do
  if ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no \
         -p "$PORT" -i "$SSH_KEY" "${ANSIBLE_USER}@${host}" "exit 0" 2>/dev/null; then
    info "SSH $host OK"
  else
    error "SSH $host FAILED"
    SSH_FAILED=1
  fi
done

if [ "$SSH_FAILED" = "1" ]; then
  echo ""
  echo "  Ensure your SSH key is copied to each node:"
  echo "    ssh-copy-id -i $SSH_KEY ${ANSIBLE_USER}@<node-ip>"
  exit 1
fi

echo ""
header "=== All checks passed — running playbook ==="
echo ""

if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
  echo "  Extra args: ${EXTRA_ARGS[*]}"
fi
echo ""

# ── Pull image ────────────────────────────────────────────────────────────────
docker pull "$ANSIBLE_IMAGE"

# ── Run playbook ──────────────────────────────────────────────────────────────
docker run --rm \
  --network host \
  -v "$K3S_ANSIBLE_DIR:/ansible:ro" \
  -v "$INVENTORY:/ansible/inventory.yml:ro" \
  -v "$SSH_KEY:/root/.ssh/ansible_key:ro" \
  -e ANSIBLE_PRIVATE_KEY_FILE=/root/.ssh/ansible_key \
  -e ANSIBLE_HOST_KEY_CHECKING=False \
  "$ANSIBLE_IMAGE" \
  ansible-playbook playbooks/site.yml -i inventory.yml "${EXTRA_ARGS[@]}"
