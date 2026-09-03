#!/usr/bin/env bash
# sanitize-pr-pii.sh — Remove "Requested by" PII from PR descriptions and comments
#
# Scans every PR (open + closed) in every repo of a GitHub org. Removes lines
# matching "Requested by: @user" or "Requested by: email@..." from PR bodies,
# issue comments, and review comments.
#
# Usage:
#   ./scripts/sanitize-pr-pii.sh <GITHUB_ORG> [--dry-run]
#
# Prerequisites: gh CLI authenticated with repo + pull-request scopes, jq
set -euo pipefail

ORG="${1:?Usage: $0 <GITHUB_ORG> [--dry-run]}"
DRY_RUN=false
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=true

LOG_DIR="$(pwd)/cleanup-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/sanitize-pr-pii-$(date +%Y%m%d-%H%M%S).log"

log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG_FILE"; }

# Strip the system-appended footer (session link, requester) before scanning,
# then remove any remaining "Requested by:" lines.
sanitize_text() {
  local text="$1"
  echo "$text" \
    | sed '/^Link to Devin session:/,$d' \
    | sed '/^<!-- devin-review-badge/,$d' \
    | sed -E '/^[[:space:]]*[Rr][Ee][Qq][Uu][Ee][Ss][Tt][Ee][Dd][[:space:]]+[Bb][Yy][[:space:]]*:[[:space:]]*.*$/d'
}

has_pii() {
  echo "$1" | grep -qPi '^\s*requested\s+by\s*:\s*\S'
}

REPOS=$(gh repo list "$ORG" --limit 500 --json name --jq '.[].name' | sort)
TOTAL_REPOS=$(echo "$REPOS" | wc -l)
TOTAL_EDITS=0
REPO_NUM=0

for REPO_NAME in $REPOS; do
  REPO_NUM=$((REPO_NUM + 1))
  FULL_REPO="$ORG/$REPO_NAME"
  log "[$REPO_NUM/$TOTAL_REPOS] Processing $FULL_REPO"

  # --- PR descriptions ---
  PAGE=1
  while true; do
    PR_JSON=$(gh api "repos/$FULL_REPO/pulls?state=all&per_page=100&page=$PAGE" 2>/dev/null || echo "[]")
    PR_COUNT=$(echo "$PR_JSON" | jq 'length')
    [[ "$PR_COUNT" -eq 0 ]] && break

    for i in $(seq 0 $((PR_COUNT - 1))); do
      PR_NUM=$(echo "$PR_JSON" | jq -r ".[$i].number")
      PR_BODY=$(echo "$PR_JSON" | jq -r ".[$i].body // empty")

      if [[ -n "$PR_BODY" ]] && has_pii "$PR_BODY"; then
        NEW_BODY=$(sanitize_text "$PR_BODY")
        if [[ "$DRY_RUN" == true ]]; then
          log "  [DRY-RUN] Would sanitize PR #$PR_NUM description"
        else
          PAYLOAD=$(jq -n --arg body "$NEW_BODY" '{"body": $body}')
          if echo "$PAYLOAD" | gh api "repos/$FULL_REPO/pulls/$PR_NUM" -X PATCH --input - >/dev/null 2>&1; then
            log "  Sanitized PR #$PR_NUM description"
            TOTAL_EDITS=$((TOTAL_EDITS + 1))
          else
            log "  ERROR: Failed to edit PR #$PR_NUM description"
          fi
        fi
      fi
    done
    PAGE=$((PAGE + 1))
  done

  # --- Issue/PR comments ---
  PAGE=1
  while true; do
    COMMENT_JSON=$(gh api "repos/$FULL_REPO/issues/comments?per_page=100&page=$PAGE" 2>/dev/null || echo "[]")
    COMMENT_COUNT=$(echo "$COMMENT_JSON" | jq 'length')
    [[ "$COMMENT_COUNT" -eq 0 ]] && break

    for i in $(seq 0 $((COMMENT_COUNT - 1))); do
      COMMENT_ID=$(echo "$COMMENT_JSON" | jq -r ".[$i].id")
      COMMENT_BODY=$(echo "$COMMENT_JSON" | jq -r ".[$i].body // empty")

      if [[ -n "$COMMENT_BODY" ]] && has_pii "$COMMENT_BODY"; then
        NEW_BODY=$(sanitize_text "$COMMENT_BODY")
        if [[ "$DRY_RUN" == true ]]; then
          log "  [DRY-RUN] Would sanitize comment $COMMENT_ID"
        else
          PAYLOAD=$(jq -n --arg body "$NEW_BODY" '{"body": $body}')
          if echo "$PAYLOAD" | gh api "repos/$FULL_REPO/issues/comments/$COMMENT_ID" -X PATCH --input - >/dev/null 2>&1; then
            log "  Sanitized comment $COMMENT_ID"
            TOTAL_EDITS=$((TOTAL_EDITS + 1))
          else
            log "  ERROR: Failed to edit comment $COMMENT_ID"
          fi
        fi
      fi
    done
    PAGE=$((PAGE + 1))
  done

  # --- PR review comments (inline code review) ---
  PAGE=1
  while true; do
    REVIEW_JSON=$(gh api "repos/$FULL_REPO/pulls/comments?per_page=100&page=$PAGE" 2>/dev/null || echo "[]")
    REVIEW_COUNT=$(echo "$REVIEW_JSON" | jq 'length')
    [[ "$REVIEW_COUNT" -eq 0 ]] && break

    for i in $(seq 0 $((REVIEW_COUNT - 1))); do
      REVIEW_ID=$(echo "$REVIEW_JSON" | jq -r ".[$i].id")
      REVIEW_BODY=$(echo "$REVIEW_JSON" | jq -r ".[$i].body // empty")

      if [[ -n "$REVIEW_BODY" ]] && has_pii "$REVIEW_BODY"; then
        NEW_BODY=$(sanitize_text "$REVIEW_BODY")
        if [[ "$DRY_RUN" == true ]]; then
          log "  [DRY-RUN] Would sanitize review comment $REVIEW_ID"
        else
          PAYLOAD=$(jq -n --arg body "$NEW_BODY" '{"body": $body}')
          if echo "$PAYLOAD" | gh api "repos/$FULL_REPO/pulls/comments/$REVIEW_ID" -X PATCH --input - >/dev/null 2>&1; then
            log "  Sanitized review comment $REVIEW_ID"
            TOTAL_EDITS=$((TOTAL_EDITS + 1))
          else
            log "  ERROR: Failed to edit review comment $REVIEW_ID"
          fi
        fi
      fi
    done
    PAGE=$((PAGE + 1))
  done

  sleep 0.5
done

log ""
log "=== PII Sanitization Complete ==="
log "Repos scanned: $TOTAL_REPOS | Edits: $TOTAL_EDITS"
log "Log: $LOG_FILE"
