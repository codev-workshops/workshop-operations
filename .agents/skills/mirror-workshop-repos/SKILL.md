---
name: mirror-workshop-repos
description: >
  Mirror the GitHub repos required by a workshop into a private target org.
  Use when the user says they need to set up, host, or mirror repos for a
  workshop from the Cognition-Partner-Workshops org. Reads the workshop
  README to find the "Repos Required" section, extracts repo names, and
  runs scripts/clone-repo.sh with a GitHub PAT.
triggers: ["user"]
---

## Overview

This skill mirrors the public repos required by a workshop into a private
GitHub org so attendees can use them in a Devin Enterprise environment.

The user will reference a workshop by name or by URL from the
`workshop-instructions` repo (e.g.
`workshops/application-development-maintenance/README.md`). You will read
that README, extract the repos listed under **Repos Required**, and run
`scripts/clone-repo.sh` to create private copies in the target org.

## Step 1: Identify the workshop

Ask the user which workshop they want to set up if not already specified.

Workshops live in the `workshop-instructions` repo at:
```
https://github.com/Cognition-Partner-Workshops/workshop-instructions/blob/main/workshops/<workshop-name>/README.md
```

If the user provides a URL, extract the workshop path from it.
If they provide a name, look it up under `workshops/`.

## Step 2: Read the workshop README and extract repos

Fetch the raw workshop README from GitHub:
```
https://raw.githubusercontent.com/Cognition-Partner-Workshops/workshop-instructions/main/workshops/<workshop-name>/README.md
```

Find the **## Repos Required** section. Repos are listed as checkboxes:
```
- [ ] timesheet-app
- [ ] uc-spring-boot-upgrade-microservice-extraction
- [ ] ts-java-angular-jhipster (optional, for Lab A1 Option B)
```

Extract all repo names from the checkbox lines. Note which are marked
`(optional, ...)` — present the full list to the user and let them confirm
which repos to include.

## Step 3: Check for the GitHub PAT

The script needs a GitHub fine-grained PAT stored in `GITHUB_MIRROR_PAT`.

Check if the environment variable is set:
```bash
echo "${GITHUB_MIRROR_PAT:+set}"
```

If it is NOT set, ask the user:

> I need a GitHub fine-grained personal access token (PAT) to create
> private repos in the target org. Here's how to create one:
>
> 1. Go to https://github.com/settings/personal-access-tokens/new
> 2. **Token name:** `devin-workshop-mirror` (or any name)
> 3. **Expiration:** 7 days (or as needed)
> 4. **Resource owner:** Select the **target organization** (e.g. `Cognition-Partner-Workshops-mirror`)
> 5. **Repository access:** "All repositories"
> 6. **Repository permissions:**
>    - **Contents:** Read and write
>    - **Administration:** Read and write
>    - **Metadata:** Read-only (auto-granted)
> 7. Click **Generate token** and copy it.
>
> Note: If the target org requires admin approval for PATs, an org admin
> must approve the token at `https://github.com/organizations/<ORG>/settings/personal-access-tokens/active`.

Once the user provides the token, export it:
```bash
export GITHUB_MIRROR_PAT="<token>"
```

## Step 4: Run clone-repo.sh

From the operator repo root, run the script with all the confirmed repo
names. The default target org is `Cognition-Partner-Workshops-mirror`.

```bash
export GITHUB_MIRROR_PAT="<token>"
./scripts/clone-repo.sh <repo1> <repo2> <repo3> ... \
  --target-org=<TARGET_ORG>
```

If the user specifies a different target org, use `--target-org=<their-org>`.

The script:
- Copies only the default branch by default (use `--all-branches` if needed)
- Strips `.github/workflows/` from mirrors by default
- Skips repos that already exist in the target org
- Blocks `workshop-metadata` and `workshop-instructions` automatically
- Prints an OK/Skipped/Blocked/Failed summary

## Step 5: Report results

After the script completes, report:
1. Which repos were successfully mirrored
2. Which were skipped (already existed)
3. Which failed (if any — suggest fixes)
4. Remind the user to:
   - Ensure the Devin GitHub App is installed on the target org with access to these repos
   - Run `provision-workshop.sh` if they need to create a Devin org for attendees
