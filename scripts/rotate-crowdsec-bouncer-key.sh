#!/usr/bin/env bash
# Rotate the CrowdSec bouncer API key for Traefik.
# Deletes the old bouncer registration, generates a new key,
# and updates the middleware YAML inline.
#
# Usage: ./scripts/rotate-crowdsec-bouncer-key.sh

set -euo pipefail

BOUNCER_NAME="traefik-bouncer"
MIDDLEWARE_FILE="infrastructure/crowdsec/templates/middleware.yaml"

if [[ ! -f "$MIDDLEWARE_FILE" ]]; then
  echo "Error: $MIDDLEWARE_FILE not found. Run from repo root."
  exit 1
fi

echo "Removing old bouncer registration..."
kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli bouncers delete "$BOUNCER_NAME" 2>/dev/null || true

echo "Generating new bouncer key..."
NEW_KEY=$(kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli bouncers add "$BOUNCER_NAME" -o raw)

if [[ -z "$NEW_KEY" ]]; then
  echo "Error: failed to generate bouncer key"
  exit 1
fi

echo "Updating middleware with new key..."
sed -i "s|crowdsecLapiKey: \".*\"|crowdsecLapiKey: \"$NEW_KEY\"|" "$MIDDLEWARE_FILE"

echo "Committing..."
git add "$MIDDLEWARE_FILE"
git commit -m "Rotate CrowdSec bouncer API key"

echo "Syncing ArgoCD..."
./scripts/argocd-sync.sh crowdsec
sleep 5

echo "Restarting Traefik to pick up new key..."
kubectl rollout restart deploy/traefik -n traefik
kubectl rollout status deploy/traefik -n traefik --timeout=60s

echo "Done. Verify with:"
echo "  kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli bouncers list"
