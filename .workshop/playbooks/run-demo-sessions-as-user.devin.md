# Playbook: Run a demo flow's Devin sessions in a target org, as a real user

> **Facilitator / author:** this file is the source for a **Devin Playbook**.
> Copy its contents into your Devin organization (Settings → Playbooks → *Create
> a new Playbook*) so sessions can invoke it as `!run-demo-sessions`. See
> [Creating Playbooks](https://docs.devin.ai/product-guides/creating-playbooks).

## Overview

Use this to **execute** a demo flow — not author it. You have a demo (a playbook
source, a presenter thread, before-state repos) and you need the sessions to
actually exist and be reviewable in the org where the demo will be shown, owned
by a named human rather than a service user, so a presenter can open them live.

The session you are running in is almost never the org that matters. Demo and
workshop sessions run in a **separate target org** (e.g. an org named "Demo"),
and cross-org work is only reachable through the **v3 API** with an
enterprise-scoped key. The output of this playbook is:

1. the demo's playbook registered in the target org with a working `!macro`;
2. one session per phase of the flow, created **as the requesting user**;
3. a monitoring pass that confirms each session reached a verified result
   (green controls, a PR) — with the session URLs handed back for the presenter.

## The one principle: the API is the only way into another org

Devin's own management tools (`devin_playbook_manage`, `devin_session_create`
and friends) operate on **the org this session runs in**. Anything you create
with them lands in the wrong place and is invisible to the demo. Every step here
goes through `https://<host>/api/v3/...` with the enterprise key, scoped
explicitly by `org_id`. Two corollaries worth internalizing:

- **A 403 usually means the wrong `org_id`, not a bad key.** `Missing required
  permission 'org.devins.use' on <org>` reads like a scope problem and is almost
  always an ID problem. Confirm the ID against
  `GET /v3/enterprise/organizations` before assuming the key needs reissuing.
- **Never guess an org ID.** They are opaque and there is more than one
  plausible-looking candidate. Get it from the API or from the user.

## Required from user

- **The target org ID** (`org-…`). Ask if you do not have it; do not infer it
  from a previous session's notes without confirming against the API.
- **An enterprise API key** (`cog_`-prefixed) in the secrets store, with
  `org.devins.use`, `org.sessions.view`, `ImpersonateOrgSessions`, and playbook
  write. Offer to save it at org scope so later sessions inherit it.
- **The user to impersonate** — their Devin `user_id` (e.g. `google-oauth2|…`).
  They must already be a member of the target org.
- **The flow** — which phases become sessions, and the prompt for each. Take the
  prompts **verbatim from the presenter thread** so what you run is what the
  presenter will read out.

## Procedure

1. **Resolve identity and target.** `GET /v3/self` to confirm the key
   authenticates; `GET /v3/enterprise/organizations` to confirm the org ID and
   name; `GET /v3/enterprise/organizations/{org_id}/members/users` to confirm the
   impersonation target is a member (look up their `user_id` by email here rather
   than asking them to find it).
2. **Check the org's existing playbooks first.**
   `GET /v3/organizations/{org_id}/playbooks` — search titles *and* bodies before
   registering anything. Orgs accumulate near-duplicates; extending an existing
   playbook beats adding a fourth variant of it.
3. **Register the playbook with its macro in one call.**
   `POST /v3/organizations/{org_id}/playbooks` with `title`, `body`, and `macro`.
   Include the macro on creation: `PATCH` on a playbook returns **405**, and the
   only way to add one afterwards is `PUT .../playbooks/{playbook_id}` with the
   *complete* object (title + body + macro), since PUT replaces rather than
   merges. Playbook creation ignores impersonation — the record will show the
   service user as `created_by`, which is expected and harmless.
4. **Create one session per phase.**
   `POST /v3/organizations/{org_id}/sessions` with `prompt`, `title`,
   `create_as_user_id`, and `repos` (the repos the phase needs; a session that
   cannot see the before-state repo will waste its first minutes failing to
   clone). Reference the playbook from the prompt by `!macro` so you are
   exercising the registered artifact rather than a pasted copy. Script the
   creation loop rather than issuing calls by hand so it is repeatable.
5. **Verify impersonation and macro resolution actually happened.** Do not
   assume either. `GET /v3/organizations/{org_id}/sessions/{session_id}` and
   check `user_id` is the impersonated human and `playbook_id` is the playbook
   you registered. `origin` will read `api`.
6. **Monitor to a verified result.** Poll the same endpoint (or
   `GET /v3/organizations/{org_id}/sessions` for the whole set) on a loop and
   watch `status`, `status_detail`, `pull_requests`, `structured_output`, and
   `child_session_ids`. `suspended` + `status_detail: inactivity` means the
   session is waiting on a human, not that it failed — read its result before
   reporting anything. For a fan-out phase, follow `child_session_ids` into the
   children; they **inherit the parent's `user_id` and `playbook_id`**, so the
   whole tree stays under the impersonated user.
7. **Report the flow as a table** of phase → session URL → output (PR, parity
   result), and say plainly which outputs are run output versus starting state.

## Specifications (postconditions)

- Every session appears in the target org under the impersonated user, not the
  service user — verified by reading back `user_id`, not inferred.
- Sessions that were meant to use the playbook have a non-null `playbook_id`.
- Each phase reached a real result: a PR, green controls, or an explicit
  blocker. A created session is not a completed phase.
- Fan-out phases have children, and the children are accounted for individually.
- The creation script and prompts are kept (in `/home/ubuntu/prompts/` or the
  repo) so the flow can be re-run before the next event.
- No demo/run output is merged into the before-state `main`.

## Advice and pointers

- Write the creation and monitoring loops as two small scripts. You will re-run
  both — monitoring especially, and polling by hand across four or more sessions
  burns time and drops sessions.
- Prompts belong to the presenter thread, not to you. If a prompt has to change
  to make the run work, change the thread too; a divergence between what runs
  and what the presenter reads is a live-demo failure waiting to happen.
- Launch the phases together rather than in sequence when they do not depend on
  each other's output — the fan-out phase is itself the demo of parallelism.
- Feed the live run back into the demo. A real run typically surfaces findings
  the author's static analysis missed; those are the most credible content in the
  thread. Verify them against `main` before writing them in.
- Watch ACU limits. If the org's `max_cycle_acu_limit` is 0 or null, every
  session suspends immediately with `org_usage_limit_exceeded`.
- Keep the key out of shell history and logs — pass it via the environment, and
  never echo it.

## Forbidden actions

- Do **not** use the Devin MCP management tools to create playbooks, sessions,
  automations, or schedules for another org. They act on the current org only.
- Do **not** impersonate a user other than the one who asked, and do not
  impersonate at all without an explicit request.
- Do **not** report a flow as working because sessions were created. Read each
  session's actual output first.
- Do **not** merge the run output into the before-state `main` — the flow must
  stay repeatable for the next run.
- Do **not** paste a playbook body into a prompt as a substitute for registering
  it; the point is that the `!macro` works in that org.
- Do **not** include customer-identifying content or identify the requester in
  PRs, commits, or session titles.
