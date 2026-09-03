# Playbook: Author a Devin demo flow (with the verification loop)

> **Facilitator / author:** this file is the source for a **Devin Playbook**.
> Copy its contents into your Devin organization (Settings → Playbooks → *Create
> a new Playbook*) so sessions can invoke it as `!author-devin-demo`. See
> [Creating Playbooks](https://docs.devin.ai/product-guides/creating-playbooks).
> It is also registered in the org via the Devin MCP/API.

## Overview

Use this when you want to build a **new Devin demo** — a showcase that proves
Devin can do a real engineering job (a migration, an upgrade, a remediation, a
test-generation pass) with a **programmatic verification loop** that gives
confidence in the result. The output is three decoupled artifacts plus a working
end-to-end run:

1. a **portable Devin Playbook** (the general, reusable procedure) — `.workshop/playbooks/<name>.devin.md` in the code repo;
2. a **repo Skill** (the repo-specific mechanics) — `.agents/skills/<name>/SKILL.md` in the code repo, auto-loaded when Devin works there;
3. a **presenter thread** (the single linear demo guide) — `workshop-metadata/demos/<category>/<name>-demo.md`.

A good Devin demo does not show a finished artifact and say "run it." It shows
**Devin doing the work** off a playbook, **proving** each step against a source
of truth, catching a real divergence, fixing it, and fanning the work out in
parallel — then runs the produced artifact and confirms completion in the target
tool. The confidence comes from programmatic verification, not from "looks
reasonable" review.

## The `.workshop/` paradigm

`.workshop/` is a convention directory that lives **in a code/use-case repo** (or
in this operator repo) and holds demo-authoring assets that are *not* application
code and are *not* auto-loaded by Devin:

- `.workshop/playbooks/*.devin.md` — **portable Devin Playbook sources.** Each is
  a general, reusable procedure formatted per the Creating-Playbooks guide. The
  `.devin.md` extension signals it is drag-and-droppable into a Devin org. These
  are **not** auto-loaded; a facilitator copies them into the org (Settings →
  Playbooks, or via the v3 API / Devin MCP) so sessions invoke them by `!macro`.

Contrast with the two sibling conventions a demo uses:

| Artifact | Lives in | Loading | Scope |
|---|---|---|---|
| **Playbook** (`.workshop/playbooks/*.devin.md`) | the code repo | copied into the org by the facilitator; invoked via `!macro` | portable, general procedure |
| **Skill** (`.agents/skills/<name>/SKILL.md`) | the code repo | auto-loaded by Devin when working in the repo | repo-specific mechanics (commands, paths, namespaces) |
| **Presenter thread** (`demos/.../*-demo.md`) | `workshop-metadata` | read by the presenter | the single linear demo script |

Keep the boundary clean: portable procedure → Playbook; repo mechanics → Skill;
the linear narrative → presenter thread. Facilitator-only logistics (copy the
playbook into the org, day-of setup, pacing) belong in the **operator** repo, not
in the attendee-facing `workshop-metadata` repo.

## Required from user

- **The use case** — a source → target (or before → after) engineering task with
  a real repo, e.g. "convert SAS to Databricks", "upgrade Spring Boot 2 → 3",
  "remediate CVEs". Name it per the repo-naming convention (`uc-…`, `ts-…`).
- **The verification** — the programmatic check that *proves* success: tests,
  a reconciliation/parity harness, a build + lint + typecheck, a CI gate. If you
  cannot state how success is proven programmatically, stop and define that first
  — it is the heart of the demo.
- **The repos** — what Devin reads (the source/before) and writes (the target).
- **The Devin features to showcase** — at minimum the differentiators in
  *Specifications* below; call out which ones this use case leans on hardest.

## Procedure

1. **Choose a verifiable outcome.** Pick a task whose correctness can be proven
   by code, not opinion. Define the source of truth (the legacy code, a spec, a
   golden dataset) and the controls that gate "done" (parity checks, tests,
   build/lint/CI). Ground everything in a real repo — verify file paths and
   counts against `main`.
2. **Stage before vs after as parallel / repeatable / reversible.** Put the
   durable "before" on `main` (tooling, harness, seed/setup, the playbook source,
   the Skill). Keep the "after" as the work Devin produces live — an unmerged
   branch, or outputs written to an isolated **namespace** so concurrent runs
   never collide. The demo must be safe to repeat and easy to revert.
3. **Write the portable Playbook** at `.workshop/playbooks/<name>.devin.md`,
   formatted per the Creating-Playbooks guide: Overview, the one guiding
   principle, Required from user, Procedure, Specifications (postconditions),
   Advice, Forbidden actions. Include a **worked example of a real bug the
   verification caught** — that is the credibility beat.
4. **Write the repo Skill** at `.agents/skills/<name>/SKILL.md` (YAML
   frontmatter `name` + `description`) holding the repo-specific mechanics the
   Playbook deliberately omits: exact commands, namespaces, where the controls
   live, deploy/revert. Devin auto-loads it when working in the repo.
5. **Write the presenter thread** in `workshop-metadata/demos/<category>/` as a
   single linear thread (see that repo's `demos/AGENTS.md`): lead with prompts,
   minimal preamble, "Key Takeaways" summary. Structure it as: orient over the
   estate → do one unit of work live **with verification** (catch + fix a real
   divergence) → fan out in parallel → confidence = programmatic verification →
   run the produced artifact → **confirm completion in the target tool's
   dashboard** (what to open and what each view proves). Reference the procedure
   by its `!macro`; keep facilitator setup out (it lives in operator).
6. **Showcase Devin's differentiated value** explicitly across the thread — wire
   in the items in *Specifications* where they fit naturally (do not bolt them
   on).
7. **Register and validate.** Register the Playbook in the org (v3 API
   `POST /v3/organizations/{org_id}/playbooks` or Devin MCP `devin_playbook_manage`),
   then launch a session that invokes the `!macro` end-to-end and confirm it runs
   the loop to a green verification and opens a PR. A demo you have not run is not
   done.

## Specifications (the Devin-value checklist the demo must hit)

A strong Devin demo makes these differentiators concrete, not abstract:

- **Programmatic verification loop** — the confidence story. Devin builds, runs
  the controls, hits a real failure, fixes it against the source of truth, and
  goes green. Show a genuine bug being caught (the centerpiece), not a staged one.
- **Orchestrator → child fan-out** — one Devin session spawns a **child session
  per unit of work** and monitors them to green: one agent dividing and
  conquering across a wave, each child on its own namespace/branch, each opening
  its own verified PR. (See child sessions / parallel fan-out.)
- **Scheduled Devins** — recurring sessions for Operations, Maintenance, and
  quality-of-life work (nightly smoke tests, weekly dependency bumps, a recurring
  reconciliation sweep). Show that the same playbook runs unattended on a cadence.
- **Isolated workspace as a feature, not a flaw** — each session/child runs in
  its own VM with its **own scoped credentials and namespace**. Isolation is what
  makes parallel runs safe, reproducible, and non-colliding; per-session secrets
  mean blast-radius is contained. Frame it as a strength.
- **Devin Automations** — event-driven triggers that start sessions
  automatically: a CI failure auto-fixed, a Slack/Linear/webhook event triaged,
  a cron schedule. See [Automations](https://docs.devin.ai/product-guides/automations).
  Use where sensible for the use case (e.g. "on CI failure, Devin reruns the
  conversion loop and pushes a fix").
- **Devin Playbooks** — the procedure codified once and invoked by `!macro` so
  every run (and every child) is consistent across the team.
- **The shared context layer** — Knowledge notes, DeepWiki over the repo, and MCP
  integrations that let Devin orient over an unfamiliar estate in minutes.
- **The PR + Devin Review feedback loop** — every unit of work lands as a PR with
  an automated reviewer; the demo shows the collaboration/review model, not a
  black box.

## Advice and pointers

- Lead with the verification loop. If a viewer remembers one thing, it should be
  "Devin proved the work was correct and caught a real mistake."
- A real caught bug beats any narration. Mine the actual run for a divergence the
  controls flagged and make it the worked example in both the Playbook and the
  presenter thread.
- Keep the three artifacts decoupled. When in doubt: portable → Playbook,
  repo-specific → Skill, narrative → presenter thread.
- Respect the repos' conventions. `workshop-metadata` allows "demo" verbiage only
  under `demos/`, wants single-linear-thread demo docs, "Key Takeaways", and no
  facilitator-only logistics (those go to operator). Follow `AGENTS.md` /
  `REVIEW.md` in each repo.
- Make it repeatable and reversible from day one: namespaces or unmerged
  branches, a durable `main`, a one-command revert.
- No overstatement for probabilistic capabilities (DeepWiki, AI analysis) — use
  "typically", "coverage depends on repo structure".

## Forbidden actions

- Do **not** merge the "after"/answer-key into `main` — `main` is the durable
  before-state so the demo repeats. Keep the live-produced work on a branch or in
  a disposable namespace.
- Do **not** put facilitator-only setup or day-of logistics in the
  `workshop-metadata` (attendee-facing) repo — that content lives in operator.
- Do **not** ship a demo whose "verification" is not actually programmatic, or
  whose success can only be judged by eye.
- Do **not** include customer-identifying content or identify the requester in
  PRs/commits (multi-tenant privacy).
- Do **not** claim platform capabilities the workshop environment does not
  support.
