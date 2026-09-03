#!/usr/bin/env bash
# mirror-github-org.sh — Mirror repos from one GitHub org to another.
#
# Creates independent copies (not forks) of each repo. Optionally strips
# .github/workflows/ from all branches so mirrored repos don't trigger
# unrelated CI in the target org.
#
# Usage:
#   ./scripts/mirror-github-org.sh <SOURCE_ORG> <TARGET_ORG> [OPTIONS]
#
# Options:
#   --dry-run              Preview without creating repos
#   --include=<glob>       Only mirror repos matching this pattern (e.g. "uc-*")
#   --exclude=<glob>       Skip repos matching this pattern (repeatable)
#   --no-default-excludes  Don't auto-exclude workshop-metadata and operator
#   --skip-existing        Skip repos that already exist in target (default)
#   --no-skip-existing     Overwrite existing repos
#   --visibility=<v>       Target repo visibility: public, private (default: private)
#   --strip-workflows      Remove .github/workflows/ from all branches (default)
#   --no-strip-workflows   Keep workflows as-is
#   --config=<file>        Read repo list from a workshop config JSON instead of listing the source org
#   --source-host=<host>   GitHub hostname for the source org (default: github.com)
#   --target-host=<host>   GitHub hostname for the target org (default: github.com)
#
# Prerequisites:
#   - gh CLI authenticated with admin:org, repo scopes for both orgs
#     (if source and target are on different hosts, authenticate to both:
#      gh auth login --hostname github.com
#      gh auth login --hostname ghes.example.com)
#   - git, jq
#
# Note: This creates independent copies, not git mirrors. Lab-specific changes
# in the target org won't be overwritten by future runs (with --skip-existing).
set -euo pipefail

SOURCE_ORG="${1:?Usage: $0 <SOURCE_ORG> <TARGET_ORG> [OPTIONS]}"
TARGET_ORG="${2:?Usage: $0 <SOURCE_ORG> <TARGET_ORG> [OPTIONS]}"
shift 2

DRY_RUN=false
INCLUDE_PATTERN=""
EXCLUDE_PATTERN=""
SKIP_EXISTING=true
VISIBILITY="private"
STRIP_WORKFLOWS=true
CONFIG_FILE=""
SOURCE_HOST="github.com"
TARGET_HOST="github.com"

# workshop-metadata is excluded by default because its hyperlinks reference
# the source org URLs and would be broken in a private mirror.  Facilitators
# should use their local AI coding agent with the agent prompt in
# templates/agent-prompt-setup-event.md to selectively copy relevant content.
DEFAULT_EXCLUDES="workshop-metadata|operator"

for arg in "$@"; do
  case "$arg" in
    --dry-run)             DRY_RUN=true ;;
    --include=*)           INCLUDE_PATTERN="${INCLUDE_PATTERN:+$INCLUDE_PATTERN|}${arg#*=}" ;;
    --exclude=*)           EXCLUDE_PATTERN="${EXCLUDE_PATTERN:+$EXCLUDE_PATTERN|}${arg#*=}" ;;
    --no-default-excludes) DEFAULT_EXCLUDES="" ;;
    --skip-existing)       SKIP_EXISTING=true ;;
    --no-skip-existing)    SKIP_EXISTING=false ;;
    --visibility=*)        VISIBILITY="${arg#*=}" ;;
    --strip-workflows)     STRIP_WORKFLOWS=true ;;
    --no-strip-workflows)  STRIP_WORKFLOWS=false ;;
    --config=*)            CONFIG_FILE="${arg#*=}" ;;
    --source-host=*)       SOURCE_HOST="${arg#*=}" ;;
    --target-host=*)       TARGET_HOST="${arg#*=}" ;;
    -h|--help)
      sed -n '2,/^[^#]/{ /^#/s/^# \?//p }' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

# Merge default excludes into the user-supplied exclude pattern
if [[ -n "$DEFAULT_EXCLUDES" ]]; then
  EXCLUDE_PATTERN="${EXCLUDE_PATTERN:+$EXCLUDE_PATTERN|}${DEFAULT_EXCLUDES}"
fi

LOGDIR="./mirror-logs"
mkdir -p "$LOGDIR"
LOGFILE="$(cd "$(dirname "$LOGDIR")" && pwd)/$(basename "$LOGDIR")/mirror-$(date +%Y%m%d-%H%M%S).log"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOGFILE"; }

source_api() { gh api --hostname "$SOURCE_HOST" "$@"; }
target_api() { gh api --hostname "$TARGET_HOST" "$@"; }

source_git_url() { echo "https://${SOURCE_HOST}/${SOURCE_ORG}/${1}.git"; }
target_git_url() { echo "https://${TARGET_HOST}/${TARGET_ORG}/${1}.git"; }

log "=== GitHub Org Mirror ==="
log "Source: ${SOURCE_ORG} (${SOURCE_HOST}) -> Target: ${TARGET_ORG} (${TARGET_HOST})"
log "Visibility: ${VISIBILITY} | Strip workflows: ${STRIP_WORKFLOWS} | Dry run: ${DRY_RUN}"

# ---------------------------------------------------------------------------
# Pre-flight: verify gh is authenticated to both hosts
# ---------------------------------------------------------------------------
for host in "$SOURCE_HOST" "$TARGET_HOST"; do
  if ! gh auth status --hostname "$host" >/dev/null 2>&1; then
    log "ERROR: gh CLI is not authenticated to ${host}"
    log "  Run: gh auth login --hostname ${host}"
    exit 1
  fi
done
log "Auth OK: ${SOURCE_HOST}$([ "$SOURCE_HOST" != "$TARGET_HOST" ] && echo ", ${TARGET_HOST}")"

# ---------------------------------------------------------------------------
# Collect repo names
# ---------------------------------------------------------------------------
REPO_NAMES=()

if [[ -n "$CONFIG_FILE" ]]; then
  log "Reading repos from config: ${CONFIG_FILE}"
  while IFS= read -r r; do REPO_NAMES+=("$r"); done < <(jq -r '.repos[] | split("/") | .[1]' "$CONFIG_FILE")
else
  log "Fetching repos from ${SOURCE_ORG} on ${SOURCE_HOST}..."
  api_err=$(mktemp)
  page=1
  while true; do
    if ! repos=$(source_api "orgs/${SOURCE_ORG}/repos?per_page=100&page=${page}&type=all" \
      --jq '.[].name' 2>"$api_err"); then
      log "ERROR: Failed to list repos in ${SOURCE_ORG} on ${SOURCE_HOST}:"
      log "  $(cat "$api_err")"
      rm -f "$api_err"
      exit 1
    fi
    [[ -z "$repos" ]] && break
    while IFS= read -r r; do REPO_NAMES+=("$r"); done <<< "$repos"
    page=$((page + 1))
  done
  rm -f "$api_err"
fi
log "Repos to process: ${#REPO_NAMES[@]}"

# ---------------------------------------------------------------------------
# Collect existing target repos (for skip logic)
# ---------------------------------------------------------------------------
TARGET_SET=""
TARGET_SET_COUNT=0
if [[ "$SKIP_EXISTING" == "true" ]]; then
  log "Fetching existing repos in ${TARGET_ORG} on ${TARGET_HOST}..."
  api_err=$(mktemp)
  page=1
  while true; do
    if ! repos=$(target_api "orgs/${TARGET_ORG}/repos?per_page=100&page=${page}&type=all" \
      --jq '.[].name' 2>"$api_err"); then
      log "ERROR: Failed to list repos in ${TARGET_ORG} on ${TARGET_HOST}:"
      log "  $(cat "$api_err")"
      rm -f "$api_err"
      exit 1
    fi
    [[ -z "$repos" ]] && break
    while IFS= read -r r; do
      TARGET_SET="${TARGET_SET}:${r}:"
      TARGET_SET_COUNT=$((TARGET_SET_COUNT + 1))
    done <<< "$repos"
    page=$((page + 1))
  done
  rm -f "$api_err"
  log "Existing repos in target: ${TARGET_SET_COUNT}"
fi

# ---------------------------------------------------------------------------
# Filter helpers
# ---------------------------------------------------------------------------
is_filtered_out() {
  local name="$1"
  if [[ -n "$INCLUDE_PATTERN" ]]; then
    # shellcheck disable=SC2254
    case "$name" in $INCLUDE_PATTERN) ;; *) return 0 ;; esac
  fi
  if [[ -n "$EXCLUDE_PATTERN" ]]; then
    # shellcheck disable=SC2254
    case "$name" in $EXCLUDE_PATTERN) return 0 ;; esac
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Mirror loop
# ---------------------------------------------------------------------------
mirrored=0 skipped=0 failed=0

for repo_name in "${REPO_NAMES[@]}"; do
  if is_filtered_out "$repo_name"; then
    log "SKIP (filter): ${repo_name}"
    skipped=$((skipped + 1))
    continue
  fi

  if [[ "$SKIP_EXISTING" == "true" && "$TARGET_SET" == *":${repo_name}:"* ]]; then
    log "SKIP (exists): ${repo_name}"
    skipped=$((skipped + 1))
    continue
  fi

  default_branch=$(source_api "repos/${SOURCE_ORG}/${repo_name}" --jq '.default_branch' 2>/dev/null || echo "main")
  description=$(source_api "repos/${SOURCE_ORG}/${repo_name}" --jq '.description // ""' 2>/dev/null || echo "")

  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY RUN: Would mirror ${repo_name} (branch: ${default_branch})"
    mirrored=$((mirrored + 1))
    continue
  fi

  log "Mirroring: ${repo_name}..."

  clone_dir="${WORK_DIR}/${repo_name}.git"

  # Clone bare from source
  if ! git clone --bare "$(source_git_url "$repo_name")" "$clone_dir" 2>>"$LOGFILE"; then
    log "FAIL (clone): ${repo_name}"
    failed=$((failed + 1))
    continue
  fi

  # Strip workflows from all branches if requested
  if [[ "$STRIP_WORKFLOWS" == "true" ]]; then
    local_dir="${WORK_DIR}/${repo_name}-work"
    git clone "$clone_dir" "$local_dir" 2>>"$LOGFILE"
    cd "$local_dir"

    for remote_branch in $(git branch -r | grep -v HEAD | sed 's|origin/||' | xargs); do
      git branch --track "$remote_branch" "origin/$remote_branch" 2>/dev/null || true
    done

    for branch in $(git branch | sed 's/^[* ]*//' | xargs); do
      git checkout "$branch" 2>>"$LOGFILE" || continue
      if [[ -d ".github/workflows" ]]; then
        rm -rf ".github/workflows"
        git add -A && git commit -m "Remove CI workflows for workshop mirror" 2>>"$LOGFILE" || true
      fi
    done

    git checkout "$default_branch" 2>>"$LOGFILE"
    cd - >/dev/null

    rm -rf "$clone_dir"
    git clone --bare "$local_dir" "$clone_dir" 2>>"$LOGFILE"
    rm -rf "$local_dir"
  fi

  # Create target repo
  if ! target_api "orgs/${TARGET_ORG}/repos" \
    -X POST \
    -f name="$repo_name" \
    -f description="$description" \
    -f visibility="$VISIBILITY" \
    -F auto_init=false \
    --silent 2>>"$LOGFILE"; then
    log "FAIL (create): ${repo_name}"
    failed=$((failed + 1))
    rm -rf "$clone_dir"
    continue
  fi

  # Push all branches and tags
  cd "$clone_dir"
  if ! git push --mirror "$(target_git_url "$repo_name")" 2>>"$LOGFILE"; then
    log "FAIL (push): ${repo_name}"
    failed=$((failed + 1))
    cd - >/dev/null
    rm -rf "$clone_dir"
    continue
  fi
  cd - >/dev/null

  rm -rf "$clone_dir"
  log "OK: ${repo_name}"
  mirrored=$((mirrored + 1))

  sleep 0.5
done

log ""
log "=== Mirror Summary ==="
log "Mirrored: ${mirrored} | Skipped: ${skipped} | Failed: ${failed}"
log "Log: ${LOGFILE}"
