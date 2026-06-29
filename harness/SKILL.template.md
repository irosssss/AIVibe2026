---
# harness/SKILL.template.md — template for a reviewable task playbook.
# A skill is executable instruction. Review a new/edited SKILL.md like code (audit item I3).
# NOTE: AIVibe's *runtime* skills (design_advisor, furniture_matcher, budget_optimizer) live in
# Swift at AIVibe/Core/AI/Skills/SkillIndex.swift and are NOT defined by this markdown — this
# template is for dev-side / coding-agent playbooks that operate ON the repo.
name: <skill-id>                 # kebab-case, == folder name
description: >                   # ONE sentence — what the router matches on
  Trigger when the user wants to <do X> in the AIVibe repo. Be concrete about inputs and the
  on-disk deliverable.
scenario: engineering            # design | marketing | engineering | product | …
surface: backend                 # ios | backend | both
risk: low                        # low (read/draft) | medium (writes code) | high (touches §6 paths)
example_prompt: "<a line that should select this skill>"
---

# <Skill display name>

One paragraph: what on-disk change it produces and the single job it does well.

## When to use / not use

Use when: <specific situations>.
Don't use when: <adjacent task that belongs elsewhere; touching §6-protected paths without a
direct request; anything that needs the runtime providers changed>.

## Inputs to gather first (ask, don't assume)

Confirm before generating: surface (iOS vs backend) · which feature/module · the relevant tests ·
any Blueprint § involved · acceptance check. For a fresh/ambiguous brief, ask a short intake
(audit item B5) and show something small early.

## Pre-flight (enforced)

1. Read `AGENTS.md` (trust model §5, action policy §6, commands §3) and `CLAUDE.md`.
2. Read the target file(s) and their tests before editing.
3. Confirm the change is not in a §6-protected path; if it is, stop and ask.

## Procedure

1. Write/raise a `PLAN.md` with checkable steps (resume from first unchecked on a fresh context).
2. Make the smallest correct change, matching surrounding code.
3. Self-verify after each step (next section). Never advance past a red gate.
4. State exactly what changed and why; cite Blueprint § for AI-logic changes.

## Output contract

- A real, reviewable diff in the repo — never prose about a change.
- Russian comments/logs per project convention; `public` types; `Sendable + Codable + Equatable`
  DTOs; no new npm deps in the backend hot path.
- No secret, `.env`, or local config staged.

## Self-check (before done — audit B3 / §7)

- [ ] matches the confirmed brief, not a generic version
- [ ] `swiftlint --strict` green (iOS) / `node --check` + `cd backend && node --test` green (backend)
- [ ] `node scripts/code-complexity-analyzer.mjs` adds no new WARN
- [ ] no lorem / TODO / broken paths; no weakening of promptGuard / PermissionEngine / fallback
- [ ] `git check-ignore` clean for any secret/local path
