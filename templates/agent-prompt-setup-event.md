# Agent Prompt: Set Up a Workshop Event

Use this prompt with a **local AI coding agent** (Devin, Cursor, Copilot, etc.)
to provision a new workshop event end-to-end.  The agent will drive the operator
scripts to mirror repos, create the Devin org, set permissions, and prepare
environment configs.

> **Why not clone workshop-metadata?**  The `workshop-metadata` repo contains
> hyperlinks that reference `Cognition-Partner-Workshops` URLs.  In a private
> mirror those links would be broken.  Instead, the agent reads workshop-metadata
> locally and copies only the relevant module/workshop content into the event
> config — rewriting links as needed.

---

## Prerequisites

Before pasting the prompt below, make sure:

1. **`gh` CLI** is authenticated with `admin:org` + `repo` scopes for both the
   source org (`Cognition-Partner-Workshops`) and the target org.
2. **`DEVIN_API_KEY`** environment variable is set to a `cog_`-prefixed
   enterprise service user key with the required permissions
   (`ManageOrganizations`, `ManageGitIntegrations`, `ManageOrgSessions`,
   `ImpersonateOrgSessions`, `ManageAccountMembership`).
3. You have a local clone of both:
   - `Cognition-Partner-Workshops/operator`
   - `Cognition-Partner-Workshops/workshop-metadata`

---

## Prompt — paste into your local AI coding agent

````text
I need to set up a new Devin Enterprise workshop event.  Walk me through the
process using the scripts in the `operator` repo.

### What I need you to do

1. **Ask me which workshops or modules I want.**
   - List the available workshops from `workshop-metadata/workshops/` (read
     each README.md to show the workshop name, focus, and duration).
   - List the available modules from `workshop-metadata/modules/` grouped by
     category.
   - Let me pick by name, track, or category.

2. **Identify the repos required.**
   - For each selected workshop/module, parse the "Repos Used" or
     "Repos Required" section (and inline `**Repositories:**` entries) to
     build the full list of repos needed.
   - Show me the list and let me confirm or adjust.

3. **Create private mirrors of the repos.**
   - Run a single command with all repo names:
     ```
     ./scripts/clone-repo.sh <REPO_A> <REPO_B> <REPO_C> ... \
       --target-org=<TARGET_ORG>
     ```
   - The script processes them in sequence and prints a summary.
   - Do NOT mirror `workshop-metadata` — its hyperlinks would be broken
     (the script blocks it automatically).
   - Do NOT mirror `operator` into the attendee org — it goes into the
     internal operations org only (see step 6).

4. **Create a workshop config file.**
   - Copy `configs/_template.json` to `configs/<event-slug>.json`.
   - Fill in: event_name, org_name, repos (pointing to the target org
     mirrors), ACU limits, and any other fields I provide.
   - Ask me for: event name, target org name, participant emails file
     (optional), enterprise/org role IDs (optional).

5. **Provision the attendee Devin org.**
   - Run:
     ```
     ./scripts/provision-workshop.sh --config configs/<event-slug>.json
     ```
   - This creates the Devin org, sets git permissions for the mirrored
     repos, invites participants, and kicks off environment config setup
     sessions (one per repo).
   - Show me the output (org ID, session URLs).

6. **Copy the operator repo into the internal operations org.**
   - The operator repo itself should be mirrored into the facilitator's
     internal Devin org (the same enterprise, but NOT the attendee org):
     ```
     ./scripts/clone-repo.sh operator \
       --target-org=<INTERNAL_OPS_ORG>
     ```
   - Then add git permissions for it in the internal ops Devin org so
     facilitators can run operator scripts from Devin sessions.

7. **Summarize next steps.**
   - Print a checklist of what was provisioned.
   - Remind me to:
     - Monitor the setup sessions in the Devin webapp
     - Share the workshop org URL with participants
     - Run `./scripts/cleanup-all.sh` and `./scripts/teardown-workshop.sh`
       after the event

### Important rules

- **Never clone `workshop-metadata` directly** — read it locally, extract
  the repos each lab needs, and only mirror the app/code repos.
- **The `operator` repo goes to the internal ops org**, not the attendee org.
- All mirrored repos default to **private** visibility.
- CI workflows are **stripped** from mirrors by default (use
  `--no-strip-workflows` to keep them).
- If a repo already exists in the target org, it is **skipped** by default
  (use `--no-skip-existing` to overwrite).
````

---

## What the agent will do

When you paste this prompt, the agent will interactively:

1. Show you available workshops and modules from `workshop-metadata/`
2. Let you pick which ones to include in the event
3. Resolve the full repo list from workshop/module content
4. Run `clone-repo.sh` for each repo to create private mirrors
5. Generate a workshop config JSON
6. Run `provision-workshop.sh` to create the Devin org with permissions,
   participant invites, and environment config sessions
7. Mirror the operator repo into the internal ops org
8. Print a post-provisioning checklist

The entire flow is driven by the agent reading `workshop-metadata/` locally
— no cloning of workshop-metadata into the mirror org is needed.
