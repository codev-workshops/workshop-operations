#!/usr/bin/env bash
# teardown-workshop.sh — Post-workshop cleanup
#
# Clears git permissions and optionally deletes the workshop organization.
#
# Usage:
#   ./teardown-workshop.sh --org-id org-xxxxx
#   ./teardown-workshop.sh --org-id org-xxxxx --delete-org
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/manage-org.sh"
source "${SCRIPT_DIR}/lib/manage-repos.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
ORG_ID=""
DELETE_ORG=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org-id)     ORG_ID="$2"; shift 2 ;;
    --delete-org) DELETE_ORG=true; shift ;;
    -h|--help)
      echo "Usage: $0 --org-id <org-id> [--delete-org]"
      echo
      echo "Options:"
      echo "  --org-id <id>    Organization ID to tear down (required)"
      echo "  --delete-org     Also delete the organization (default: only clear permissions)"
      exit 0
      ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -z "$ORG_ID" ]] && die "Missing required --org-id argument. Run with --help for usage."

echo
echo "============================================"
echo "  Workshop Teardown"
echo "============================================"
echo "  Org ID     : ${ORG_ID}"
echo "  Delete org : ${DELETE_ORG}"
echo "============================================"
echo

# ---------------------------------------------------------------------------
# Step 1: Show current state
# ---------------------------------------------------------------------------
info "Current git permissions:"
perms=$(list_git_permissions "$ORG_ID")
perm_count=$(echo "$perms" | jq length)
echo "$perms" | jq -r '.[] | "  \(.repo_path)"'
echo
info "Found ${perm_count} permission(s)"
echo

# ---------------------------------------------------------------------------
# Step 2: Clear git permissions
# ---------------------------------------------------------------------------
if [[ "$perm_count" -gt 0 ]]; then
  info "Clearing git permissions..."
  clear_git_permissions "$ORG_ID" > /dev/null
  info "Cleared ${perm_count} permission(s)"
else
  info "No permissions to clear"
fi
echo

# ---------------------------------------------------------------------------
# Step 3: Optionally delete the organization
# ---------------------------------------------------------------------------
if [[ "$DELETE_ORG" == "true" ]]; then
  echo
  warn "Deleting organization ${ORG_ID}..."
  warn "This is irreversible. Proceeding in 5 seconds (Ctrl+C to abort)..."
  sleep 5
  delete_org "$ORG_ID"
else
  info "Organization ${ORG_ID} preserved (use --delete-org to remove)"
fi
echo

echo "============================================"
echo "  Teardown Complete"
echo "============================================"
