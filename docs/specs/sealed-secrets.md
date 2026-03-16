# Sealed Secrets

## Executive Summary

Sealed Secrets is a Kubernetes controller that allows secrets to be encrypted into
`SealedSecret` custom resources that are safe to commit to Git. The controller runs
in the cluster and is the only thing that can decrypt them, using a private key it
manages internally. This spec covers deploying the Sealed Secrets controller via
ArgoCD as the first infrastructure component, making it the foundation that all
subsequent application secrets depend on. Once deployed, any Kubernetes Secret
in this cluster should be created as a SealedSecret in this repo rather than
applied manually.

**Author:** Drew Locketz
**Date:** 2026-03-15
**Status:** Draft

---

## Tasks

- [ ] 1. Apply `clusters/home/root-app.yaml` to bootstrap ArgoCD self-management
- [ ] 2. Add the Sealed Secrets Helm chart as the source for `infrastructure/sealed-secrets/`
- [ ] 3. Verify ArgoCD picks up and syncs the `sealed-secrets` Application
- [ ] 4. Verify the `sealed-secrets` controller pod is `Running` in the `sealed-secrets` namespace
- [ ] 5. Install the `kubeseal` CLI locally
- [ ] 6. Fetch the controller's public key and store it in the repo at `bootstrap/sealed-secrets-pub-cert.pem`
- [ ] 7. Verify a test secret can be sealed and applied successfully

---

## Components

```
  This repo
  ┌──────────────────────────────────────────────┐
  │  infrastructure/sealed-secrets/              │
  │  └── helmrelease.yaml  (or Chart values)     │
  └──────────────────┬───────────────────────────┘
                     │ ArgoCD syncs
                     ▼
  ┌──────────────────────────────────────────────┐
  │              k3s Cluster                     │
  │                                              │
  │  namespace: sealed-secrets                   │
  │  ┌────────────────────────────────────┐      │
  │  │   sealed-secrets controller        │      │
  │  │   (bitnami/sealed-secrets)         │      │
  │  │                                    │      │
  │  │   holds private key                │      │
  │  │   decrypts SealedSecrets ──────────┼───┐  │
  │  └────────────────────────────────────┘   │  │
  │                                           │  │
  │  ┌────────────────────┐                   │  │
  │  │   SealedSecret     │ ──── decrypts ────┘  │
  │  │   (in Git, safe)   │                      │
  │  └────────────────────┘                      │
  │            │                                 │
  │            ▼                                 │
  │  ┌────────────────────┐                      │
  │  │   Secret           │                      │
  │  │   (in cluster)     │                      │
  │  └────────────────────┘                      │
  └──────────────────────────────────────────────┘

  Local machine
  ┌──────────────────────────────────────────────┐
  │  kubeseal --cert bootstrap/sealed-secrets-   │
  │           pub-cert.pem                       │
  │  < mysecret.yaml > mysealedsecret.yaml       │
  │                                              │
  │  (encrypts without needing cluster access)   │
  └──────────────────────────────────────────────┘
```

---

## Success Criteria

- [ ] `kubectl get pods -n sealed-secrets` shows controller `Running`
- [ ] `kubectl get crds | grep sealedsecret` shows the CRD is installed
- [ ] A test `SealedSecret` can be created with `kubeseal` and successfully decrypted by the controller
- [ ] The controller's public key is stored at `bootstrap/sealed-secrets-pub-cert.pem`
- [ ] `root-app`, `infrastructure-app`, and `sealed-secrets` applications are visible and `Synced` in ArgoCD

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `docs/specs/argocd-bootstrap.md` | ArgoCD installation — required before this spec can be implemented |
| `infrastructure/apps/sealed-secrets.yaml` | ArgoCD Application manifest pointing to `infrastructure/sealed-secrets/` |
| https://github.com/bitnami-labs/sealed-secrets | Official Sealed Secrets repo and Helm chart |

---

## Design Decisions

### Decision: Helm chart vs raw manifests for Sealed Secrets

**Options considered:**
- Raw manifests from the Sealed Secrets GitHub releases
- Helm chart (`sealed-secrets/sealed-secrets`)

**Decision:** Helm chart. The Sealed Secrets Helm chart is well-maintained by Bitnami and
makes version upgrades straightforward via a values file. ArgoCD has native Helm support
so no additional tooling is required.

**Trade-offs:** Requires the Helm chart repo to be reachable from the cluster. No meaningful downside.

---

### Decision: Store public cert in repo

**Options considered:**
- Fetch the public cert fresh from the cluster each time a secret needs sealing
- Store the public cert in the repo at `bootstrap/sealed-secrets-pub-cert.pem`

**Decision:** Store in repo. The public cert is not sensitive — it can only encrypt, not decrypt.
Storing it in the repo means secrets can be sealed offline without cluster access, which is
useful when preparing manifests before deployment.

**Trade-offs:** If the controller's private key is rotated, the public cert in the repo
must be updated and all existing SealedSecrets re-encrypted.
