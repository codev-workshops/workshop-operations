#!/usr/bin/env bash
# delete-stale-branches.sh — Delete branches with no commits in N weeks
#
# Deletes remote branches whose last commit is older than the threshold.
# Always preserves the default branch. Useful for cleaning up after workshops
# where participants create many short-lived branches.
#
# Usage:
#   ./scripts/delete-stale-branches.sh <GITHUB_ORG> [--stale-weeks=3] [--dry-run]
#
# Prerequisites: gh CLI authenticated with repo scope
set -euo pipefail

ORG="${1:?Usage: $0 <GITHUB_ORG> [--stale-weeks=3] [--dry-run]}"
shift

STALE_WEEKS=3
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --stale-weeks=*) STALE_WEEKS="${arg#*=}" ;;
    --dry-run)       DRY_RUN=true ;;
  esac
done

LOG_DIR="$(pwd)/cleanup-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/delete-stale-branches-$(date +%Y%m%d-%H%M%S).log"

log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG_FILE"; }

CUTOFF_DATE=$(date -u -d "${STALE_WEEKS} weeks ago" +%Y-%m-%dT%H:%M:%SZ)
log "Cutoff: ${CUTOFF_DATE} (branches older than ${STALE_WEEKS} weeks)"
log "Dry run: ${DRY_RUN}"
log ""

REPOS=$(gh repo list "$ORG" --limit 500 --json name --jq '.[].name' | sort)
TOTAL_REPOS=$(echo "$REPOS" | wc -l)
TOTAL_DELETED=0
REPO_NUM=0

for REPO_NAME in $REPOS; do
  REPO_NUM=$((REPO_NUM + 1))
  FULL_REPO="$ORG/$REPO_NAME"
  log "[$REPO_NUM/$TOTAL_REPOS] Processing $FULL_REPO"

  DEFAULT_BRANCH=$(gh repo view "$FULL_REPO" --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")

  PAGE=1
  while true; do
    BRANCHES=$(gh api "repos/$FULL_REPO/branches?per_page=100&page=$PAGE" \
      --jq '.[] | "\(.name)\t\(.commit.sha)"' 2>/dev/null || true)
    [[ -z "$BRANCHES" ]] && break

    while IFS=$'\t' read -r BRANCH_NAME COMMIT_SHA; do
      [[ "$BRANCH_NAME" == "$DEFAULT_BRANCH" ]] && continue

      COMMIT_DATE=$(gh api "repos/$FULL_REPO/commits/$COMMIT_SHA" \
        --jq '.commit.committer.date' 2>/dev/null || true)
      [[ -z "$COMMIT_DATE" ]] && continue

      if [[ "$COMMIT_DATE" < "$CUTOFF_DATE" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
          log "  [DRY-RUN] Would delete: ${BRANCH_NAME} (last commit: ${COMMIT_DATE})"
        else
          if gh api "repos/$FULL_REPO/git/refs/heads/$BRANCH_NAME" -X DELETE >/dev/null 2>&1; then
            log "  Deleted: ${BRANCH_NAME} (last commit: ${COMMIT_DATE})"
            TOTAL_DELETED=$((TOTAL_DELETED + 1))
          else
            log "  ERROR: Failed to delete ${BRANCH_NAME}"
          fi
        fi
      fi
    done <<< "$BRANCHES"

    PAGE=$((PAGE + 1))
  done

  sleep 0.5
done

log ""
log "=== Stale Branch Cleanup Complete ==="
log "Repos scanned: ${TOTAL_REPOS} | Branches deleted: ${TOTAL_DELETED}"
log "Log: ${LOG_FILE}"
