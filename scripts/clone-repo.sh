#!/usr/bin/env bash
# clone-repo.sh — Create private copies of one or more public repos
#
# Takes one or more repo names from the source GitHub org and creates
# independent private copies in the target org.  This is the single-/multi-repo
# equivalent of mirror-github-org.sh — intended to be called by a local AI
# coding agent or a facilitator setting up repos on demand.
#
# By default only the default branch is copied (like the "copy default branch
# only" option in the GitHub fork UI).  Use --all-branches or --branches=a,b,c
# to include additional branches.
#
# Usage:
#   ./scripts/clone-repo.sh <REPO_NAME>... [OPTIONS]
#
# Positional:
#   REPO_NAME...           One or more repo names (just repo name, not org/repo)
#
# Options:
#   --source-org=<org>     Source GitHub org (default: Cognition-Partner-Workshops)
#   --target-org=<org>     Target GitHub org (default: Cognition-Partner-Workshops-mirror)
#   --source-host=<host>   GitHub hostname for the source (default: github.com)
#   --target-host=<host>   GitHub hostname for the target (default: github.com)
#   --visibility=<v>       Target repo visibility: public, private (default: private)
#   --all-branches         Copy all branches (default: default branch only)
#   --branches=<a,b,c>     Copy only these branches (comma-separated)
#   --strip-workflows      Remove .github/workflows/ from copied branches (default)
#   --no-strip-workflows   Keep workflows as-is
#   --skip-existing        Skip if the repo already exists in target (default)
#   --no-skip-existing     Overwrite if it already exists
#   --dry-run              Preview without creating anything
#
# Prerequisites:
#   - gh CLI authenticated with admin:org, repo scopes
#   - git, jq
#
# Examples:
#   # Clone a single repo (default branch only)
#   ./scripts/clone-repo.sh uc-bdd-test-generation-rest-api
#
#   # Clone multiple repos in one command
#   ./scripts/clone-repo.sh otterworks uc-bdd-test-generation-rest-api ts-angular-realworld-example-app
#
#   # Copy all branches
#   ./scripts/clone-repo.sh otterworks --all-branches
#
#   # Copy only specific branches
#   ./scripts/clone-repo.sh uc-legacy-modernization-cobol-to-java --branches=main,java
#
#   # Preview without creating anything
#   ./scripts/clone-repo.sh otterworks ts-angular-realworld-example-app --dry-run
set -euo pipefail

SOURCE_ORG="Cognition-Partner-Workshops"
TARGET_ORG="Cognition-Partner-Workshops-mirror"
SOURCE_HOST="github.com"
TARGET_HOST="github.com"
VISIBILITY="private"
STRIP_WORKFLOWS=true
SKIP_EXISTING=true
DRY_RUN=false
BRANCH_MODE="default"   # "default" | "all" | "specific"
BRANCH_LIST=()           # used when BRANCH_MODE=specific

REPO_NAMES=()

for arg in "$@"; do
  case "$arg" in
    --source-org=*)       SOURCE_ORG="${arg#*=}" ;;
    --target-org=*)       TARGET_ORG="${arg#*=}" ;;
    --source-host=*)      SOURCE_HOST="${arg#*=}" ;;
    --target-host=*)      TARGET_HOST="${arg#*=}" ;;
    --visibility=*)       VISIBILITY="${arg#*=}" ;;
    --all-branches)       BRANCH_MODE="all" ;;
    --branches=*)         BRANCH_MODE="specific"; IFS=',' read -ra BRANCH_LIST <<< "${arg#*=}" ;;
    --strip-workflows)    STRIP_WORKFLOWS=true ;;
    --no-strip-workflows) STRIP_WORKFLOWS=false ;;
    --skip-existing)      SKIP_EXISTING=true ;;
    --no-skip-existing)   SKIP_EXISTING=false ;;
    --dry-run)            DRY_RUN=true ;;
    -h|--help)
      sed -n '2,/^[^#]/{ /^#/s/^# \?//p }' "$0"
      exit 0
      ;;
    -*)
      echo "Unknown option: $arg" >&2; exit 1 ;;
    *)
      REPO_NAMES+=("$arg") ;;
  esac
done

if [[ ${#REPO_NAMES[@]} -eq 0 ]]; then
  echo "Usage: $0 <REPO_NAME>... [OPTIONS]" >&2
  echo "  Pass one or more repo names. Run with --help for details." >&2
  exit 1
fi

# Repos that should not be mirrored directly
BLOCKED_REPOS="workshop-metadata workshop-instructions"

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

# Resolve the PAT: prefer GITHUB_MIRROR_PAT, fall back to MIRROR_TOKEN
_PAT="${GITHUB_MIRROR_PAT:-${MIRROR_TOKEN:-}}"

# If a PAT is set, use curl directly to bypass gh proxy.
# Otherwise fall back to gh api.
if [[ -n "$_PAT" ]]; then
  source_api() {
    local endpoint="$1"; shift
    local method="GET"
    local data_args=()
    local jq_filter=""
    local silent=false
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -X) method="$2"; shift 2 ;;
        -f) data_args+=("$2"); shift 2 ;;
        -F) data_args+=("$2"); shift 2 ;;
        --jq) jq_filter="$2"; shift 2 ;;
        --silent) silent=true; shift ;;
        *) shift ;;
      esac
    done
    local url="https://api.${SOURCE_HOST}/${endpoint}"
    local result http_code
    if [[ "$method" == "GET" ]]; then
      http_code=$(curl -s -o /tmp/_api_resp.json -w "%{http_code}" -H "Authorization: Bearer ${_PAT}" -H "Accept: application/vnd.github+json" "$url")
      result=$(cat /tmp/_api_resp.json)
      if [[ "$http_code" -ge 400 ]]; then
        if [[ "$silent" == "true" ]]; then return 1; fi
        echo "$result" >&2
        return 1
      fi
    else
      # Build JSON body from -f/-F args
      local json_body="{}"
      for arg in "${data_args[@]}"; do
        local key="${arg%%=*}"
        local val="${arg#*=}"
        if [[ "$val" == "true" || "$val" == "false" ]]; then
          json_body=$(echo "$json_body" | jq --arg k "$key" --argjson v "$val" '. + {($k): $v}')
        else
          json_body=$(echo "$json_body" | jq --arg k "$key" --arg v "$val" '. + {($k): $v}')
        fi
      done
      http_code=$(curl -s -o /tmp/_api_resp.json -w "%{http_code}" -X "$method" -H "Authorization: Bearer ${_PAT}" -H "Accept: application/vnd.github+json" "$url" -d "$json_body")
      result=$(cat /tmp/_api_resp.json)
      if [[ "$http_code" -ge 400 ]]; then
        if [[ "$silent" == "true" ]]; then return 1; fi
        echo "$result" >&2
        return 1
      fi
    fi
    if [[ -n "$jq_filter" ]]; then
      echo "$result" | jq -r "$jq_filter"
    elif [[ "$silent" == "true" ]]; then
      echo "$result" > /dev/null
    else
      echo "$result"
    fi
  }
  target_api() { source_api "$@"; }
else
  source_api() { gh api --hostname "$SOURCE_HOST" "$@"; }
  target_api() { gh api --hostname "$TARGET_HOST" "$@"; }
fi

source_git_url() { echo "https://${SOURCE_HOST}/${SOURCE_ORG}/${1}.git"; }
target_git_url() {
  if [[ -n "$_PAT" ]]; then
    echo "https://x-access-token:${_PAT}@${TARGET_HOST}/${TARGET_ORG}/${1}.git"
  else
    echo "https://${TARGET_HOST}/${TARGET_ORG}/${1}.git"
  fi
}

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
if [[ -z "$_PAT" ]]; then
  for host in "$SOURCE_HOST" "$TARGET_HOST"; do
    if ! gh auth status --hostname "$host" >/dev/null 2>&1; then
      log "ERROR: gh CLI is not authenticated to ${host}"
      log "  Run: gh auth login --hostname ${host}"
      exit 1
    fi
  done
fi

branch_label="default branch only"
if [[ "$BRANCH_MODE" == "all" ]]; then
  branch_label="all branches"
elif [[ "$BRANCH_MODE" == "specific" ]]; then
  branch_label="branches: ${BRANCH_LIST[*]}"
fi

log "=== Clone Repos ==="
log "Repos:    ${REPO_NAMES[*]}"
log "Source:   ${SOURCE_ORG} (${SOURCE_HOST})"
log "Target:   ${TARGET_ORG} (${TARGET_HOST})"
log "Branches: ${branch_label}"
log "Visibility: ${VISIBILITY} | Strip workflows: ${STRIP_WORKFLOWS} | Dry run: ${DRY_RUN}"
log ""

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

OK_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0
BLOCKED_COUNT=0

# ---------------------------------------------------------------------------
# Process each repo
# ---------------------------------------------------------------------------
for REPO_NAME in "${REPO_NAMES[@]}"; do
  log "--- ${REPO_NAME} ---"

  # Check blocked list
  is_blocked=false
  for blocked in $BLOCKED_REPOS; do
    if [[ "$REPO_NAME" == "$blocked" ]]; then
      is_blocked=true
      break
    fi
  done
  if [[ "$is_blocked" == "true" ]]; then
    log "BLOCKED: '${REPO_NAME}' should not be cloned directly."
    log "  Its hyperlinks reference source org URLs that would be broken in a mirror."
    log "  Instead, read it directly to identify the repos you need, then mirror"
    log "  those repos. See the mirror-workshop-repos skill or templates/agent-prompt-setup-event.md."
    BLOCKED_COUNT=$((BLOCKED_COUNT + 1))
    continue
  fi

  # Check if target already exists
  if [[ "$SKIP_EXISTING" == "true" ]]; then
    if target_api "repos/${TARGET_ORG}/${REPO_NAME}" --silent >/dev/null 2>&1; then
      log "SKIP: ${REPO_NAME} already exists in ${TARGET_ORG}"
      SKIP_COUNT=$((SKIP_COUNT + 1))
      continue
    fi
  fi

  # Fetch source metadata
  default_branch=$(source_api "repos/${SOURCE_ORG}/${REPO_NAME}" --jq '.default_branch' 2>/dev/null || echo "main")
  description=$(source_api "repos/${SOURCE_ORG}/${REPO_NAME}" --jq '.description // ""' 2>/dev/null || echo "")

  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY RUN: Would clone ${REPO_NAME} (default branch: ${default_branch}, mode: ${branch_label})"
    OK_COUNT=$((OK_COUNT + 1))
    continue
  fi

  # -----------------------------------------------------------------------
  # Clone source
  # -----------------------------------------------------------------------
  log "Cloning ${REPO_NAME} from ${SOURCE_ORG}..."
  local_dir="${WORK_DIR}/${REPO_NAME}-work"

  if [[ "$BRANCH_MODE" == "default" ]]; then
    if ! git clone --single-branch --branch "$default_branch" \
         "$(source_git_url "$REPO_NAME")" "$local_dir" 2>&1; then
      log "FAIL: Could not clone ${SOURCE_ORG}/${REPO_NAME}"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      continue
    fi
    branches_to_push=("$default_branch")
  else
    if ! git clone "$(source_git_url "$REPO_NAME")" "$local_dir" 2>&1; then
      log "FAIL: Could not clone ${SOURCE_ORG}/${REPO_NAME}"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      continue
    fi
    pushd "$local_dir" >/dev/null

    if [[ "$BRANCH_MODE" == "all" ]]; then
      # Track every remote branch locally
      for rb in $(git branch -r | grep -v HEAD | sed 's|origin/||' | xargs); do
        git branch --track "$rb" "origin/$rb" 2>/dev/null || true
      done
      IFS=$'\n' read -r -d '' -a branches_to_push < <(git branch | sed 's/^[* ]*//' | xargs -n1 && printf '\0') || true
    else
      # Specific branches requested
      branches_to_push=()
      for b in "${BRANCH_LIST[@]}"; do
        if git branch -r | grep -q "origin/${b}$"; then
          git branch --track "$b" "origin/$b" 2>/dev/null || true
          branches_to_push+=("$b")
        else
          log "WARN: branch '${b}' not found in ${REPO_NAME}, skipping"
        fi
      done
      if [[ ${#branches_to_push[@]} -eq 0 ]]; then
        log "FAIL: None of the requested branches exist in ${REPO_NAME}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        popd >/dev/null
        rm -rf "$local_dir"
        continue
      fi
    fi
    popd >/dev/null
  fi

  # -----------------------------------------------------------------------
  # Strip workflows (if enabled) on each branch we're pushing
  # -----------------------------------------------------------------------
  if [[ "$STRIP_WORKFLOWS" == "true" ]]; then
    pushd "$local_dir" >/dev/null
    for branch in "${branches_to_push[@]}"; do
      git checkout "$branch" 2>&1 || continue
      if [[ -d ".github/workflows" ]]; then
        rm -rf ".github/workflows"
        git add -A && git commit -m "Remove CI workflows for workshop mirror" 2>&1 || true
      fi
    done
    git checkout "$default_branch" 2>&1 || git checkout "${branches_to_push[0]}" 2>&1
    popd >/dev/null
  fi

  # -----------------------------------------------------------------------
  # Create target repo
  # -----------------------------------------------------------------------
  log "Creating ${TARGET_ORG}/${REPO_NAME} (${VISIBILITY})..."
  if ! target_api "orgs/${TARGET_ORG}/repos" \
    -X POST \
    -f name="$REPO_NAME" \
    -f description="$description" \
    -f visibility="$VISIBILITY" \
    -F auto_init=false \
    --silent 2>&1; then
    log "FAIL: Could not create ${TARGET_ORG}/${REPO_NAME}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    rm -rf "$local_dir"
    continue
  fi

  # -----------------------------------------------------------------------
  # Push selected branches + tags
  # -----------------------------------------------------------------------
  log "Pushing ${#branches_to_push[@]} branch(es) and tags..."
  pushd "$local_dir" >/dev/null
  git remote add target "$(target_git_url "$REPO_NAME")" 2>/dev/null || \
    git remote set-url target "$(target_git_url "$REPO_NAME")"

  push_failed=false
  for branch in "${branches_to_push[@]}"; do
    if ! git push target "$branch" 2>&1; then
      log "FAIL: Could not push branch '${branch}' to ${TARGET_ORG}/${REPO_NAME}"
      push_failed=true
    fi
  done
  # Always push tags
  git push target --tags 2>&1 || true

  popd >/dev/null
  rm -rf "$local_dir"

  if [[ "$push_failed" == "true" ]]; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi

  log "OK: ${TARGET_ORG}/${REPO_NAME} (${#branches_to_push[@]} branch(es))"
  OK_COUNT=$((OK_COUNT + 1))
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log ""
log "=== Summary ==="
log "  OK:      ${OK_COUNT}"
log "  Skipped: ${SKIP_COUNT}"
log "  Blocked: ${BLOCKED_COUNT}"
log "  Failed:  ${FAIL_COUNT}"
log "  Total:   ${#REPO_NAMES[@]}"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
