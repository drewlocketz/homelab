# Migrate Homelab Repo to GitHub

## Executive Summary

Move this homelab repository from a local-only git repo to a public GitHub repository. This enables contributing from multiple machines and standard GitHub workflows (PRs, branch protection). ArgoCD will be reconfigured to sync from GitHub via webhook instead of polling a local repo.

**Author:** Drew Locketz
**Date:** 2026-04-04
**Status:** Draft

---

## Dependencies

| Spec | Why |
|---|---|
| `sealed-secrets.md` | All secrets must be sealed before the repo goes public |

---

## Human Instructions

These steps require manual action in the GitHub UI and cluster.

**1. Create the GitHub repository**
- Create a new public repository on GitHub (e.g. `drewdevlab/homelab`)
- Do not initialize with README, .gitignore, or license (we'll push the existing repo)

**2. Branch protection**
- Go to Settings > Branches > Add rule for `main`
- Require pull request reviews before merging
- Require status checks to pass (optional, no CI initially)
- Do not allow force pushes

**3. ArgoCD GitHub access**
- Generate a GitHub personal access token (fine-grained, read-only on the repo) or deploy key
- Add as a repository credential in ArgoCD

**4. ArgoCD webhook**
- In the GitHub repo, go to Settings > Webhooks > Add webhook
- Payload URL: `https://argocd.home.drewdevlab.com/api/webhook`
- Content type: `application/json`
- Secret: shared secret configured in ArgoCD
- Events: Just the push event

**5. DNS record (if not already present)**
- Ensure `argocd.home.drewdevlab.com` resolves to Traefik (should already work via wildcard)

**6. Rotate compromised secrets**
- After the repo is public, rotate the K3s cluster token and CrowdSec bouncer API key since their plaintext values will be in git history

---

## Open Questions

- [x] GitHub repo name? → `drewlocketz/homelab`
- [x] ArgoCD auth method → deploy key (repo-scoped)

---

## Tasks

### Phase 1: Secret Remediation (before going public)

- [x] 1. Move CrowdSec bouncer API key to a SealedSecret — replace plaintext key in `infrastructure/crowdsec/templates/middleware.yaml` with a reference to a sealed secret
- [x] 2. Remove K3s cluster token from `bootstrap/inventory.yml` — replace with placeholder or move to a file excluded by `.gitignore`
- [x] 3. Audit for any other plaintext secrets (grep for patterns like tokens, keys, passwords)
- [x] 4. Add `.gitignore` entries for any local-only files that shouldn't be public

### Phase 2: Repository Setup

- [x] 5. Create public GitHub repository
- [x] 6. Add GitHub remote: `git remote add origin git@github.com:drewlocketz/homelab.git`
- [x] 7. Push all branches: `git push -u origin main`
- [ ] 8. Configure branch protection on `main` (require PRs, no force push)

### Phase 3: ArgoCD Migration

- [x] 9. Add GitHub repo to ArgoCD: deploy key added via K8s secret `argocd-github-repo`
- [x] 10. Update `clusters/home/infrastructure-appset.yaml` — changed repoURL to `git@github.com:drewlocketz/homelab.git`
- [x] 11. Update `clusters/home/workloads-appset.yaml` — same repoURL change
- [ ] ~~12. Configure ArgoCD webhook secret for GitHub push events~~ — skipped, using 3-min polling + manual `scripts/argocd-sync.sh`
- [ ] ~~13. Add GitHub webhook pointing to ArgoCD's webhook endpoint~~ — skipped
- [x] 14. Verify ArgoCD detects changes pushed to GitHub and syncs automatically

### Phase 4: Post-Migration

- [x] 15. Rotate K3s cluster token (old value is in git history) — rotated, updated on node-0 and node-1. Node-2 offline, needs manual update when back.
- [x] 16. Rotate CrowdSec bouncer API key (old value is in git history) — new key sealed and committed
- [x] 17. Verify all applications sync successfully from GitHub
- [ ] 18. Test the full workflow: push to branch → open PR → merge → ArgoCD syncs

> Agents: check off each task as it is completed.

---

## Components

```
  Before (current)
  ┌──────────────────────────────────────────────────┐
  │  Local machine                                   │
  │  /home/drew/code/homelab (git repo, no remote)   │
  │                                                  │
  │  git commit ──► local repo on cluster            │
  │                      │                           │
  │                      ▼                           │
  │                 ArgoCD (polls local repo)         │
  └──────────────────────────────────────────────────┘

  After (target)
  ┌──────────────────────────────────────────────────┐
  │  Any machine                                     │
  │                                                  │
  │  git push ──► GitHub (public repo)               │
  │                   │                              │
  │                   │ webhook (push event)          │
  │                   ▼                              │
  │              ArgoCD ◄── syncs from GitHub         │
  │                   │                              │
  │                   ▼                              │
  │              k3s Cluster                          │
  └──────────────────────────────────────────────────┘

  PR workflow
  ┌──────────────────────────────────────────────────┐
  │  1. Create branch locally                        │
  │  2. Push branch to GitHub                        │
  │  3. Open PR against main                         │
  │  4. Review + merge                               │
  │  5. GitHub webhook notifies ArgoCD               │
  │  6. ArgoCD syncs changes to cluster              │
  └──────────────────────────────────────────────────┘
```

---

## Success Criteria

- [ ] No plaintext secrets in the repository
- [ ] Repo is public on GitHub with branch protection on `main`
- [ ] ArgoCD syncs from GitHub (not local repo)
- [ ] Push to `main` triggers ArgoCD sync via webhook within seconds
- [ ] Can clone, branch, and contribute from any machine
- [ ] All existing applications remain synced and healthy after migration

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `clusters/home/infrastructure-appset.yaml` | ApplicationSet with local repoURL to update |
| `clusters/home/workloads-appset.yaml` | ApplicationSet with local repoURL to update |
| `infrastructure/crowdsec/templates/middleware.yaml` | Contains plaintext bouncer API key |
| `bootstrap/inventory.yml` | Contains plaintext K3s cluster token |
| `bootstrap/sealed-secrets-pub-cert.pem` | Public cert for sealing secrets (safe to publish) |

---

## Design Decisions

### Decision: Public repository

**Options considered:**
- Private repo (free with limited collaborators on GitHub Free)
- Public repo

**Decision:** Public. GitHub Free allows unlimited public repos with all features (branch protection, webhooks, Actions). All secrets are managed via SealedSecrets which are safe to commit. Private repos on GitHub Free have limited Actions minutes and collaborator restrictions.

**Trade-offs:** Git history will contain previously committed plaintext secrets (K3s token, CrowdSec bouncer key). These must be rotated after going public.

### Decision: ArgoCD webhook over polling

**Options considered:**
- ArgoCD polls GitHub on an interval (default 3 minutes)
- GitHub webhook notifies ArgoCD on push

**Decision:** Webhook. Provides near-instant sync after merge instead of waiting up to 3 minutes. Simpler than GitHub Actions — ArgoCD has a built-in webhook receiver.

**Trade-offs:** Requires ArgoCD's webhook endpoint to be reachable from the internet (or via a tunnel). If the webhook fails, ArgoCD falls back to polling.

### Decision: Rotate secrets rather than rewrite git history

**Options considered:**
- Use `git filter-branch` or BFG to scrub secrets from history before publishing
- Publish as-is and rotate the exposed secrets

**Decision:** Rotate. History rewriting is fragile, can break ArgoCD's sync state, and gives false confidence (cached copies may persist). Rotating is simpler and definitively revokes the old values.

**Trade-offs:** Brief window where old secrets are in public history before rotation. Acceptable since both the K3s token and CrowdSec bouncer key are internal-only and not internet-reachable.

### Decision: No GitHub Actions initially

**Options considered:**
- Add CI pipeline (lint, validate manifests) via GitHub Actions
- Keep it simple, no CI

**Decision:** No Actions for now. ArgoCD validates manifests at sync time. CI can be added later if needed for pre-merge validation.

**Trade-offs:** Invalid manifests won't be caught until ArgoCD tries to sync. Acceptable for a single-contributor homelab.
