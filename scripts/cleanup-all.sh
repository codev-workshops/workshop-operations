#!/usr/bin/env bash
# cleanup-all.sh — Run all post-workshop cleanup tasks in sequence
#
# Tasks:
#   1. Sanitize "Requested by" PII from PR descriptions and comments
#   2. Close open PRs older than N weeks
#   3. Delete branches with no commits in N weeks (excluding default branch)
#
# Usage:
#   ./scripts/cleanup-all.sh <GITHUB_ORG> [--stale-weeks=3] [--dry-run]
#
# Prerequisites: gh CLI authenticated with repo + pull-request scopes
set -euo pipefail

ORG="${1:?Usage: $0 <GITHUB_ORG> [--stale-weeks=3] [--dry-run]}"
shift

STALE_WEEKS=3
DRY_RUN=""
for arg in "$@"; do
  case "$arg" in
    --stale-weeks=*) STALE_WEEKS="${arg#*=}" ;;
    --dry-run)       DRY_RUN="--dry-run" ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo "  Post-Workshop Cleanup: ${ORG}"
echo "  Stale threshold: ${STALE_WEEKS} weeks"
echo "  Dry run: ${DRY_RUN:-false}"
echo "============================================"
echo

echo ">>> Step 1/3: Sanitize PR PII"
bash "${SCRIPT_DIR}/sanitize-pr-pii.sh" "$ORG" $DRY_RUN
echo

echo ">>> Step 2/3: Close old PRs"
bash "${SCRIPT_DIR}/close-old-prs.sh" "$ORG" --older-than-weeks="$STALE_WEEKS" $DRY_RUN
echo

echo ">>> Step 3/3: Delete stale branches"
bash "${SCRIPT_DIR}/delete-stale-branches.sh" "$ORG" --stale-weeks="$STALE_WEEKS" $DRY_RUN
echo

echo "============================================"
echo "  All cleanup tasks complete"
echo "  Logs: $(pwd)/cleanup-logs/"
echo "============================================"
