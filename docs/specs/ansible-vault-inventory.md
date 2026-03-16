# Ansible Vault — Encrypt Inventory Secrets

## Executive Summary

The `bootstrap/inventory.yml` file currently contains the k3s cluster token in plaintext.
Ansible Vault is Ansible's built-in encryption tool that allows sensitive values to be
encrypted at rest and decrypted automatically at playbook runtime using a password.
This spec covers encrypting the cluster token in `bootstrap/inventory.yml` using
`ansible-vault`, rewriting git history to remove the plaintext token, and updating
the `run-k3s-ansible.sh` script to support vault-encrypted values. Once complete,
the repo will be safe to push to a public or private GitHub repository.

**Author:** Drew Locketz
**Date:** 2026-03-15
**Status:** Draft

---

## Tasks

- [ ] 1. Install ansible-vault locally (or confirm it is available via the Docker image)
- [ ] 2. Create a vault password file at `~/.ansible/vault-password` (gitignored)
- [ ] 3. Encrypt the token value in `bootstrap/inventory.yml` using `ansible-vault encrypt_string`
- [ ] 4. Verify the playbook runs correctly with the encrypted token
- [ ] 5. Rewrite git history to remove the plaintext token using BFG Repo Cleaner or `git filter-repo`
- [ ] 6. Update `run-k3s-ansible.sh` to pass `--vault-password-file` to Ansible
- [ ] 7. Document vault password management in `scripts/README.md`
- [ ] 8. Force push the rewritten history to any remotes

---

## Components

```
  bootstrap/inventory.yml
  ┌──────────────────────────────────────────┐
  │  vars:                                   │
  │    token: !vault |                       │
  │      $ANSIBLE_VAULT;1.1;AES256           │
  │      3133346...                          │  ← encrypted at rest
  └───────────────────────┬──────────────────┘
                          │ decrypted at runtime
                          ▼
  ┌──────────────────────────────────────────┐
  │  ansible-playbook site.yml               │
  │    --vault-password-file                 │
  │    ~/.ansible/vault-password             │
  └──────────────────────────────────────────┘
```

---

## Success Criteria

- [ ] `bootstrap/inventory.yml` contains no plaintext secrets
- [ ] `git log -p | grep -i token` returns no plaintext token value
- [ ] `./scripts/run-k3s-ansible.sh` runs successfully with the encrypted inventory
- [ ] Repo can be pushed to GitHub without exposing secrets

---

## Prior Artifacts

| Artifact | Description |
|---|---|
| `bootstrap/inventory.yml` | File containing the plaintext token to be encrypted |
| `scripts/run-k3s-ansible.sh` | Script that runs the playbook — needs vault flag added |
| https://docs.ansible.com/ansible/latest/vault_guide/index.html | Official Ansible Vault documentation |

---

## Design Decisions

### Decision: Encrypt only the token value vs encrypt the whole file

**Options considered:**
- Encrypt the entire `inventory.yml` file with `ansible-vault encrypt`
- Encrypt only the sensitive value using `ansible-vault encrypt_string`

**Decision:** Encrypt only the token value. Encrypting the whole file makes it unreadable in the repo — you can't see node IPs, user config, or k3s version without decrypting first. Encrypting just the secret value keeps the file readable while protecting only what matters.

**Trade-offs:** Slightly more complex syntax in the inventory file. Worth it for readability.

---

### Decision: Vault password storage

**Options considered:**
- Hardcode password in a gitignored file (`~/.ansible/vault-password`)
- Use a system keychain or secrets manager
- Prompt for password on each run

**Decision:** Gitignored file at `~/.ansible/vault-password` for now. Simple and works well for a single-operator homelab. The file must be backed up separately (e.g. in a password manager).

**Trade-offs:** If the vault password file is lost, the token must be rotated and re-encrypted. For a homelab this is acceptable.
