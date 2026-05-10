#!/usr/bin/env bash
# Rotate the ProtonVPN WireGuard key for SABnzbd.
# Usage: ./scripts/rotate-vpn-key.sh <new-wireguard-private-key>

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <wireguard-private-key>"
  exit 1
fi

KEY="$1"

echo "Creating SealedSecret..."
kubectl create secret generic sabnzbd-vpn \
  --namespace sabnzbd \
  --from-literal=WIREGUARD_PRIVATE_KEY="$KEY" \
  --dry-run=client -o yaml \
  | kubeseal \
    --controller-namespace=sealed-secrets \
    --controller-name=sealed-secrets-controller \
    --format=yaml \
  > workloads/sabnzbd/sealedsecret-vpn.yaml

echo "Deleting old secret..."
kubectl delete secret sabnzbd-vpn -n sabnzbd --ignore-not-found
kubectl delete sealedsecret sabnzbd-vpn -n sabnzbd --ignore-not-found

echo "Committing..."
git add workloads/sabnzbd/sealedsecret-vpn.yaml
git commit -m "Rotate SABnzbd VPN key"

echo "Syncing ArgoCD..."
./scripts/argocd-sync.sh sabnzbd
sleep 10

echo "Restarting SABnzbd pod..."
kubectl rollout restart deploy/sabnzbd -n sabnzbd
kubectl rollout status deploy/sabnzbd -n sabnzbd --timeout=60s

echo "Done. Check gluetun logs:"
echo "  kubectl logs -n sabnzbd deploy/sabnzbd -c gluetun --tail=5"
