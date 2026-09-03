#!/usr/bin/env bash
# provision-workshop.sh — End-to-end workshop provisioning
#
# Creates a Devin org, sets git permissions for workshop repos, and invokes
# Devin sessions to set up environment config YAMLs for each repo.
#
# Usage:
#   ./provision-workshop.sh --config configs/june-2026.json
#   ./provision-workshop.sh --config configs/june-2026.json --skip-sessions
#   ./provision-workshop.sh --config configs/june-2026.json --org-id org-existing-id
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/manage-org.sh"
source "${SCRIPT_DIR}/lib/manage-repos.sh"
source "${SCRIPT_DIR}/lib/manage-members.sh"
source "${SCRIPT_DIR}/lib/invoke-setup.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
CONFIG_FILE=""
SKIP_SESSIONS=false
SKIP_INVITES=false
EXISTING_ORG_ID=""
EMAILS_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)        CONFIG_FILE="$2"; shift 2 ;;
    --skip-sessions) SKIP_SESSIONS=true; shift ;;
    --skip-invites)  SKIP_INVITES=true; shift ;;
    --org-id)        EXISTING_ORG_ID="$2"; shift 2 ;;
    --emails-file)   EMAILS_FILE="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --config <config.json> [--skip-sessions] [--skip-invites] [--org-id <org-id>] [--emails-file <file>]"
      echo
      echo "Options:"
      echo "  --config <file>     Path to workshop config JSON (required)"
      echo "  --skip-sessions     Skip invoking Devin setup sessions"
      echo "  --skip-invites      Skip participant invitations"
      echo "  --org-id <id>       Use an existing org instead of creating one"
      echo "  --emails-file <f>   File with participant emails (one per line)"
      exit 0
      ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -z "$CONFIG_FILE" ]] && die "Missing required --config argument. Run with --help for usage."
[[ ! -f "$CONFIG_FILE" ]] && die "Config file not found: ${CONFIG_FILE}"

# ---------------------------------------------------------------------------
# Read config
# ---------------------------------------------------------------------------
info "Reading config: ${CONFIG_FILE}"

ORG_NAME=$(config_get "$CONFIG_FILE" '.org_name')
GIT_CONNECTION_ID=$(config_get "$CONFIG_FILE" '.git_connection_id')
MAX_SESSION_ACU=$(config_get "$CONFIG_FILE" '.max_session_acu_limit // 250')
MAX_CYCLE_ACU=$(config_get "$CONFIG_FILE" '.max_cycle_acu_limit // 250')
SETUP_USER_ID=$(config_get "$CONFIG_FILE" '.setup_as_user_id // empty')
SETUP_PROMPT=$(config_get "$CONFIG_FILE" '.setup_prompt_template')
ENTERPRISE_ROLE_ID=$(config_get "$CONFIG_FILE" '.enterprise_role_id // empty')
ORG_ROLE_ID=$(config_get "$CONFIG_FILE" '.org_role_id // empty')

# Use emails file from config if not overridden by CLI
if [[ -z "$EMAILS_FILE" ]]; then
  EMAILS_FILE=$(config_get "$CONFIG_FILE" '.emails_file // empty')
fi

REPOS=()
while IFS= read -r r; do REPOS+=("$r"); done < <(config_get_array "$CONFIG_FILE" '.repos')

echo
echo "============================================"
echo "  Workshop Provisioning"
echo "============================================"
echo "  Org name       : ${ORG_NAME}"
echo "  Git connection : ${GIT_CONNECTION_ID}"
echo "  Repos          : ${#REPOS[@]}"
echo "  ACU limits     : session=${MAX_SESSION_ACU}, cycle=${MAX_CYCLE_ACU}"
echo "  Setup user     : ${SETUP_USER_ID:-none (service user)}"
echo "  Emails file    : ${EMAILS_FILE:-none}"
echo "  Skip sessions  : ${SKIP_SESSIONS}"
echo "  Skip invites   : ${SKIP_INVITES}"
echo "============================================"
echo

# ---------------------------------------------------------------------------
# Step 1: Create or reuse organization
# ---------------------------------------------------------------------------
ORG_ID=""
if [[ -n "$EXISTING_ORG_ID" ]]; then
  info "Using existing org: ${EXISTING_ORG_ID}"
  ORG_ID="$EXISTING_ORG_ID"

  info "Updating ACU limits..."
  update_org "$ORG_ID" "" "$MAX_SESSION_ACU" "$MAX_CYCLE_ACU" > /dev/null
else
  info "Creating new organization..."
  org_json=$(create_org "$ORG_NAME" "$MAX_SESSION_ACU" "$MAX_CYCLE_ACU")
  ORG_ID=$(echo "$org_json" | jq -r '.org_id')
fi
echo
info "Org ID: ${ORG_ID}"
echo

# ---------------------------------------------------------------------------
# Step 2: Set git permissions (idempotent replace)
# ---------------------------------------------------------------------------
info "Setting git permissions for ${#REPOS[@]} repo(s)..."
replace_git_permissions "$ORG_ID" "$GIT_CONNECTION_ID" "${REPOS[@]}" > /dev/null
echo

info "Verifying permissions..."
list_git_permissions "$ORG_ID" | jq -r '.[] | "  \(.repo_path)"'
echo

# ---------------------------------------------------------------------------
# Step 3: Invite participants
# ---------------------------------------------------------------------------
if [[ "$SKIP_INVITES" == "true" ]] || [[ -z "$EMAILS_FILE" ]]; then
  if [[ -z "$EMAILS_FILE" ]]; then
    info "No --emails-file provided; skipping invitations"
  else
    info "Skipping invitations (--skip-invites)"
  fi
else
  if [[ ! -f "$EMAILS_FILE" ]]; then
    warn "Emails file not found: ${EMAILS_FILE}; skipping invitations"
  else
    PARTICIPANT_EMAILS=()
    while IFS= read -r r; do PARTICIPANT_EMAILS+=("$r"); done < <(read_emails_file "$EMAILS_FILE")
    if [[ ${#PARTICIPANT_EMAILS[@]} -gt 0 ]]; then
      info "Inviting ${#PARTICIPANT_EMAILS[@]} participant(s)..."
      ROLE_ARGS=()
      [[ -n "$ENTERPRISE_ROLE_ID" ]] && ROLE_ARGS+=("--enterprise-role=${ENTERPRISE_ROLE_ID}")
      [[ -n "$ORG_ROLE_ID" ]] && ROLE_ARGS+=("--org-role=${ORG_ROLE_ID}")
      invite_and_assign "$ORG_ID" "${PARTICIPANT_EMAILS[@]}" ${ROLE_ARGS[@]+"${ROLE_ARGS[@]}"}
    else
      info "No emails found in ${EMAILS_FILE}"
    fi
  fi
fi
echo

# ---------------------------------------------------------------------------
# Step 4: Invoke Devin setup sessions (one per repo)
# ---------------------------------------------------------------------------
if [[ "$SKIP_SESSIONS" == "true" ]]; then
  info "Skipping session creation (--skip-sessions)"
else
  info "Invoking setup sessions for ${#REPOS[@]} repo(s)..."
  echo

  sessions_json=$(invoke_setup_sessions "$ORG_ID" "$SETUP_PROMPT" "$SETUP_USER_ID" "${REPOS[@]}")

  echo
  echo "============================================"
  echo "  Setup Sessions"
  echo "============================================"
  echo "$sessions_json" | jq -r '.[] | "  \(.repo)\n    Session: \(.session_id)\n    URL:     \(.url)\n    Status:  \(.status)\n"'
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "============================================"
echo "  Provisioning Complete"
echo "============================================"
echo "  Org ID         : ${ORG_ID}"
echo "  Org name       : ${ORG_NAME}"
echo "  Repos          : ${#REPOS[@]}"
if [[ "$SKIP_SESSIONS" != "true" ]]; then
  echo "  Sessions       : $(echo "$sessions_json" | jq length)"
fi
echo
echo "  Next steps:"
echo "    1. Monitor setup sessions in the Devin webapp or poll via API"
echo "    2. Once sessions complete, env config YAMLs are ready for participants"
echo "    3. Share the workshop org URL with participants"
echo "    4. After the workshop: ./scripts/cleanup-all.sh <GITHUB_ORG>
    5. Tear down the org:    ./scripts/teardown-workshop.sh --org-id ${ORG_ID}"
echo
