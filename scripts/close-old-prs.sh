#!/usr/bin/env bash
# close-old-prs.sh — Close open PRs older than N weeks
#
# Closes stale PRs across all repos in a GitHub org with an explanatory comment.
# Useful for post-workshop cleanup when participants leave PRs open.
#
# Usage:
#   ./scripts/close-old-prs.sh <GITHUB_ORG> [--older-than-weeks=3] [--dry-run]
#
# Prerequisites: gh CLI authenticated with repo + pull-request scopes
set -euo pipefail

ORG="${1:?Usage: $0 <GITHUB_ORG> [--older-than-weeks=3] [--dry-run]}"
shift

OLDER_THAN_WEEKS=3
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --older-than-weeks=*) OLDER_THAN_WEEKS="${arg#*=}" ;;
    --dry-run)            DRY_RUN=true ;;
  esac
done

LOG_DIR="$(pwd)/cleanup-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/close-old-prs-$(date +%Y%m%d-%H%M%S).log"

log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG_FILE"; }

CUTOFF_DATE=$(date -u -d "${OLDER_THAN_WEEKS} weeks ago" +%Y-%m-%dT%H:%M:%SZ)
log "Cutoff: ${CUTOFF_DATE} (PRs older than ${OLDER_THAN_WEEKS} weeks)"
log "Dry run: ${DRY_RUN}"
log ""

REPOS=$(gh repo list "$ORG" --limit 500 --json name --jq '.[].name' | sort)
TOTAL_REPOS=$(echo "$REPOS" | wc -l)
TOTAL_CLOSED=0
REPO_NUM=0

for REPO_NAME in $REPOS; do
  REPO_NUM=$((REPO_NUM + 1))
  FULL_REPO="$ORG/$REPO_NAME"
  log "[$REPO_NUM/$TOTAL_REPOS] Processing $FULL_REPO"

  OPEN_PRS=$(gh pr list --repo "$FULL_REPO" --state open --limit 500 \
    --json number,createdAt,title \
    --jq '.[] | "\(.number)\t\(.createdAt)\t\(.title)"' 2>/dev/null || true)

  [[ -z "$OPEN_PRS" ]] && continue

  while IFS=$'\t' read -r PR_NUM CREATED_AT PR_TITLE; do
    if [[ "$CREATED_AT" < "$CUTOFF_DATE" ]]; then
      if [[ "$DRY_RUN" == true ]]; then
        log "  [DRY-RUN] Would close PR #${PR_NUM}: ${PR_TITLE} (created: ${CREATED_AT})"
      else
        COMMENT="Closing: this PR is older than ${OLDER_THAN_WEEKS} weeks. Reopen if still needed."
        if gh pr close "$PR_NUM" --repo "$FULL_REPO" --comment "$COMMENT" >/dev/null 2>&1; then
          log "  Closed PR #${PR_NUM}: ${PR_TITLE}"
          TOTAL_CLOSED=$((TOTAL_CLOSED + 1))
        else
          log "  ERROR: Failed to close PR #${PR_NUM}"
        fi
      fi
    fi
  done <<< "$OPEN_PRS"

  sleep 0.5
done

log ""
log "=== Old PR Cleanup Complete ==="
log "Repos scanned: ${TOTAL_REPOS} | PRs closed: ${TOTAL_CLOSED}"
log "Log: ${LOG_FILE}"
