#!/usr/bin/env bash
# invite-participants.sh — Invite users to a Devin Enterprise org
#
# Usage:
#   ./invite-participants.sh --org-id <org-id> --emails-file <file> [options]
#
# Options:
#   --org-id <id>              Devin org ID (required)
#   --emails-file <file>       File with participant emails, one per line (required)
#   --enterprise-role-id <id>  Role to assign at enterprise level
#   --org-role-id <id>         Role to assign at org level
#   --dry-run                  Preview invitations without sending
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/manage-members.sh"

ORG_ID=""
EMAILS_FILE=""
ENTERPRISE_ROLE_ID=""
ORG_ROLE_ID=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org-id)              ORG_ID="$2"; shift 2 ;;
    --emails-file)         EMAILS_FILE="$2"; shift 2 ;;
    --enterprise-role-id)  ENTERPRISE_ROLE_ID="$2"; shift 2 ;;
    --org-role-id)         ORG_ROLE_ID="$2"; shift 2 ;;
    --dry-run)             DRY_RUN=true; shift ;;
    -h|--help)
      echo "Usage: $0 --org-id <org-id> --emails-file <file> [--enterprise-role-id <id>] [--org-role-id <id>] [--dry-run]"
      exit 0
      ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -z "$ORG_ID" ]] && die "Missing required --org-id"
[[ -z "$EMAILS_FILE" ]] && die "Missing required --emails-file"

EMAILS=()
while IFS= read -r r; do EMAILS+=("$r"); done < <(read_emails_file "$EMAILS_FILE")

if [[ ${#EMAILS[@]} -eq 0 ]]; then
  info "No emails found in ${EMAILS_FILE}"
  exit 0
fi

echo
echo "============================================"
echo "  Invite Participants"
echo "============================================"
echo "  Org ID   : ${ORG_ID}"
echo "  Emails   : ${#EMAILS[@]}"
echo "  Dry run  : ${DRY_RUN}"
echo "============================================"
echo

if [[ "$DRY_RUN" == "true" ]]; then
  info "DRY RUN — would invite:"
  printf '  %s\n' "${EMAILS[@]}"
  exit 0
fi

ROLE_ARGS=()
[[ -n "$ENTERPRISE_ROLE_ID" ]] && ROLE_ARGS+=("--enterprise-role=${ENTERPRISE_ROLE_ID}")
[[ -n "$ORG_ROLE_ID" ]] && ROLE_ARGS+=("--org-role=${ORG_ROLE_ID}")

invite_and_assign "$ORG_ID" "${EMAILS[@]}" ${ROLE_ARGS[@]+"${ROLE_ARGS[@]}"}
