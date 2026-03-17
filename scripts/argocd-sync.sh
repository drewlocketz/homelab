#!/usr/bin/env bash
# Trigger a refresh and sync of all ArgoCD applications.
# Usage: ./scripts/argocd-sync.sh [app-name]
#   No argument: refreshes all applications
#   With argument: refreshes a specific application

set -euo pipefail

NAMESPACE="argocd"

refresh_app() {
  local app="$1"
  echo "Refreshing $app..."
  kubectl annotate application "$app" -n "$NAMESPACE" \
    argocd.argoproj.io/refresh=normal \
    --overwrite
}

if [[ $# -gt 0 ]]; then
  refresh_app "$1"
else
  apps=$(kubectl get applications -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
  for app in $apps; do
    refresh_app "$app"
  done
fi

echo "Done. Use 'kubectl get applications -n argocd' to check sync status."
