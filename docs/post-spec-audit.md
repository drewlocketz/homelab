# Post-Spec Audit: Placeholder Values

Generated 2026-03-17 after running `scripts/run-specs.sh`. These values were
fabricated or left as placeholders by the automated spec runner and need real
values before deploying.

---

## Requires User Input

| File | Issue | Action |
|---|---|---|
| `infrastructure/cert-manager/clusterissuer-production.yaml` | Email is `drew@yourdomain.com` | Replace with real email for Let's Encrypt |
| `infrastructure/cert-manager/clusterissuer-staging.yaml` | Email is `drew@yourdomain.com` | Replace with real email for Let's Encrypt |
| `infrastructure/cert-manager/certificate-wildcard.yaml` | Domain is `*.home.yourdomain.com` | Replace with real domain |
| `workloads/jellyfin/ingress.yaml` | Hostname is `jellyfin.home.yourdomain.com` | Replace with real domain |
| `infrastructure/monitoring/grafana-secret-sealed.yaml` | `REPLACE_WITH_KUBESEAL_OUTPUT` | Seal real Grafana admin credentials with `kubeseal` |
| `infrastructure/monitoring/alertmanager-secret-sealed.yaml` | `REPLACE_WITH_KUBESEAL_OUTPUT` | Seal real Slack webhook URL, or remove if not using Slack alerts |

## Verify

| File | Value | Action |
|---|---|---|
| `infrastructure/metallb/ipaddresspool.yaml` | IP range `10.0.4.240-10.0.4.250` | Confirm this is the desired LoadBalancer range |
| `infrastructure/traefik/values.yaml` | Traefik LB IP `10.0.4.240` | Confirm this is the desired Traefik IP |

## Already Fixed

| File | Issue | Resolution |
|---|---|---|
| `infrastructure/synology-csi/credentials-sealed.yaml` | Fabricated SealedSecret data | Replaced with real sealed credentials (commit `8b39b6b`) |
