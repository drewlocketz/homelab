# Spec-Driven Development Guide

This document defines how to write specifications for this repository. Every non-trivial task should have a spec before implementation begins. Agents must read and follow the spec for their assigned work.

---

## How to Generate a Spec

When asked to plan or implement a feature, first create a spec file in `docs/specs/` using the template below. The spec is the source of truth. Do not begin implementation until the spec is written and reviewed.

Spec files should be named descriptively, e.g. `docs/specs/argocd-bootstrap.md`.

---

## Spec Template

```markdown
# [Title]

## Executive Summary

A 2-4 sentence description of what this spec covers, why it is being done,
and what the end state looks like.

**Author:** Drew Locketz
**Date:** YYYY-MM-DD
**Status:** Draft | In Progress | Complete | Abandoned

---

## Tasks

- [ ] Task one
- [ ] Task two
- [ ] Task three

> Agents: check off each task as it is completed.

---

## Components

ASCII diagram showing the components involved and how they relate to each other.

\`\`\`
Example:

  ┌─────────────┐        ┌─────────────┐
  │   GitHub    │ ──────>│   ArgoCD    │
  │  (GitOps)   │        │  (in k3s)   │
  └─────────────┘        └──────┬──────┘
                                │ syncs
                         ┌──────▼──────┐
                         │  Workloads  │
                         └─────────────┘
\`\`\`

---

## Success Criteria

A checklist used to evaluate whether the spec was fully and correctly implemented.

- [ ] Criterion one
- [ ] Criterion two
- [ ] Criterion three

---

## Prior Artifacts

List any existing files, repos, documentation, or external resources that
informed this spec.

| Artifact | Description |
|---|---|
| `path/to/file.yaml` | Description of what it is and why it was relevant |
| https://example.com | External resource referenced |

---

## Design Decisions

Document any meaningful choices made during planning or implementation.
For each decision, note what was considered and why the chosen approach was selected.

### Decision: [Short title]

**Options considered:**
- Option A — description
- Option B — description

**Decision:** Chose Option A because...

**Trade-offs:** ...
```

---

## Rules for Agents

1. Read all files in `docs/` before starting any work in this repository.
2. If a spec exists for the task you are working on, follow it exactly.
3. Check off tasks in the spec as you complete them.
4. If you encounter a situation not covered by the spec, note it in a comment and surface it for review rather than making unilateral decisions.
5. Do not mark **Success Criteria** as complete — those are for the author to verify.
6. If no spec exists for a task, create one before proceeding and wait for approval.
