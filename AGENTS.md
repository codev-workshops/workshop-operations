# AGENTS.md — Operator Repo Guidance

Agent-facing notes for working in this repo. Keep changes scoped, use US English
spelling (e.g. *modernization*), and follow the PR conventions below.

## Mirror org is optional

This repo documents a **mirror GitHub org** model in which repos from the source
org (`Cognition-Partner-Workshops`) are copied into a mirror org
(`Cognition-Partner-Workshops-mirror`) that the Devin Enterprise GitHub App is
installed on. **This mirror model is optional, not mandatory.**

Every mention of `-mirror`, `Cognition-Partner-Workshops-mirror`, or the
"mirror org" connection anywhere in this repo — including `README.md`,
`configs/`, `scripts/`, `templates/`, `docs/`, and `.agents/skills/` — is
**only relevant if you are actually using a mirrored GitHub org.**

**If the Devin GitHub App is installed directly on the source org**
(`Cognition-Partner-Workshops`) with no `-mirror` connection at all:

- **Skip the mirroring steps entirely.** You do not need to run
  `scripts/mirror-github-org.sh` or `scripts/clone-repo.sh` to copy repos into a
  mirror org — the source-org repos are already reachable.
- **Use the source org's git connection** for the workshop org's permissions,
  and use **source-org repo paths** everywhere a `Cognition-Partner-Workshops-mirror/<repo>`
  path is shown — e.g. `Cognition-Partner-Workshops/<repo>` instead of
  `Cognition-Partner-Workshops-mirror/<repo>` in `configs/*.json` (`repos`),
  provisioning scripts, and cleanup scripts (pass the **source** org name).
- **Discover the correct `git_connection_id` per enterprise.** The value
  hardcoded in `configs/_template.json` may not exist in a given enterprise. Do
  **not** assume it — look it up with:

  ```bash
  # GET /v3/enterprise/git-providers/connections
  ./scripts/verify-auth.sh          # lists connections, or:
  curl -s -H "Authorization: Bearer $DEVIN_API_KEY" \
    https://api.devin.ai/v3/enterprise/git-providers/connections | jq .
  ```

  Pick the connection whose GitHub App is installed on the org you are actually
  using (source org when installed directly, mirror org when mirroring), and put
  that id in your config's `git_connection_id`.

The mirror workflow is still fully valid for enterprises that use it — nothing
about it is removed. This note just makes clear that it is **conditional**.

### Where mirror references appear (all conditional)

- **`README.md`** — Architecture Overview, Prerequisites, Quick Start, and
  Workflow → Phase 1 (§1.1 mirror repos) / Phase 3 (§3.1 cleanup). See the
  [Prerequisites](README.md#prerequisites) and
  [Workflow](README.md#workflow) sections.
- **`configs/_template.json`, `configs/june-2026.json`** — `git_connection_id`
  and `Cognition-Partner-Workshops-mirror/<repo>` entries in `repos`.
- **`scripts/`** — `mirror-github-org.sh`, `clone-repo.sh`, and the
  `cleanup-*` scripts that take an org name argument.
- **`templates/agent-prompt-setup-event.md`**, **`.agents/skills/mirror-workshop-repos/SKILL.md`**,
  and **`docs/`** — mirroring instructions and examples.

When the GitHub App is installed directly on the source org, read all of the
above with the mirror steps skipped and source-org paths/connection substituted.

## PR conventions

- **No PII.** Do not identify the requesting user: no names, no emails. CI runs
  a PII check that fails on `Requested by:` patterns. A link to the Devin session
  is fine (it is auto-appended); an email or name is not.
- Use **US English** spelling.
- Keep edits minimal and focused; do not rewrite or delete the existing mirror
  workflow.
