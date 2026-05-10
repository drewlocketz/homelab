#!/usr/bin/env bash
# Run claude to implement specs in dependency order.
# Skips specs that are already complete or require human steps that block automation.
#
# Usage: ./scripts/run-specs.sh [--dry-run]

set -euo pipefail

SPEC_DIR="$(cd "$(dirname "$0")/../docs/specs" && pwd)"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Specs in dependency order (all dependencies come before dependents)
SPEC_ORDER=(
  metallb
  longhorn
  cert-manager
  synology-csi
  traefik
  monitoring
  jellyfin
)

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

spec_status() {
  local spec_file="$1"
  grep -oP '^\*\*Status:\*\*\s*\K.*' "$spec_file" | xargs
}

mark_in_progress() {
  local spec_file="$1"
  sed -i 's/^\*\*Status:\*\* Draft/**Status:** In Progress/' "$spec_file"
}

mark_complete() {
  local spec_file="$1"
  sed -i 's/^\*\*Status:\*\* In Progress/**Status:** Complete/' "$spec_file"
}

echo "=== Spec Runner ==="
echo "Spec directory: $SPEC_DIR"
echo "Repo root: $REPO_ROOT"
echo ""

for spec_name in "${SPEC_ORDER[@]}"; do
  spec_file="$SPEC_DIR/${spec_name}.md"

  if [[ ! -f "$spec_file" ]]; then
    echo "SKIP $spec_name — spec file not found"
    continue
  fi

  status=$(spec_status "$spec_file")

  if [[ "$status" == "Complete" ]]; then
    echo "SKIP $spec_name — already complete"
    continue
  fi

  if [[ "$status" == "Abandoned" ]]; then
    echo "SKIP $spec_name — abandoned"
    continue
  fi

  echo ""
  echo "========================================"
  echo "  RUNNING: $spec_name"
  echo "  Status:  $status"
  echo "========================================"
  echo ""

  if [[ "$DRY_RUN" == true ]]; then
    echo "(dry run) Would run claude for $spec_name"
    continue
  fi

  mark_in_progress "$spec_file"

  PROMPT="$(cat <<EOF
You are implementing a spec for a homelab GitOps repository.

Instructions:
1. Read CLAUDE.md and README.md for project context
2. Read the spec at docs/specs/${spec_name}.md
3. Implement every task in the spec, checking them off as you go
4. Follow the spec exactly — do not add anything not specified
5. If a task requires human action (e.g. DNS setup, NAS configuration), skip it
6. When done, set the spec status to Complete
7. Commit your work with a descriptive message

Do not push to remote. Do not modify files outside the scope of the spec.
EOF
)"

  if env -u CLAUDECODE claude --dangerously-skip-permissions -p "$PROMPT"; then
    # Verify claude marked it complete; if not, mark it ourselves
    new_status=$(spec_status "$spec_file")
    if [[ "$new_status" != "Complete" ]]; then
      mark_complete "$spec_file"
    fi
    echo ""
    echo "DONE: $spec_name"
  else
    echo ""
    echo "FAILED: $spec_name (exit code $?)"
    echo "Stopping — fix the issue and re-run the script."
    echo "Remaining specs will be picked up on next run."
    exit 1
  fi
done

echo ""
echo "=== All specs processed ==="
