#!/usr/bin/env bash
# deploy-pr-pii-check.sh — Deploy the PR PII check workflow to all repos in a GitHub org
#
# Creates a PR in each target repo adding the .github/workflows/pr-pii-check.yml
# workflow. After merging, set up branch protection to require the check to pass.
#
# Usage:
#   ./scripts/deploy-pr-pii-check.sh <GITHUB_ORG> [OPTIONS]
#
# Options:
#   --dry-run           Preview what would be deployed
#   --include=<glob>    Only deploy to repos matching this pattern
#   --exclude=<glob>    Skip repos matching this pattern
#   --branch=<name>     Branch name for the PR (default: add-pii-check)
#
# Prerequisites:
#   - gh CLI authenticated with repo + workflow scopes
#   - The workflow file at .github/workflows/pr-pii-check.yml in the operator repo
set -euo pipefail

ORG="${1:?Usage: $0 <GITHUB_ORG> [OPTIONS]}"
shift

DRY_RUN=false
INCLUDE_PATTERN=""
EXCLUDE_PATTERN=""
BRANCH_NAME="add-pii-check"

for arg in "$@"; do
  case "$arg" in
    --dry-run)     DRY_RUN=true ;;
    --include=*)   INCLUDE_PATTERN="${INCLUDE_PATTERN:+$INCLUDE_PATTERN|}${arg#*=}" ;;
    --exclude=*)   EXCLUDE_PATTERN="${EXCLUDE_PATTERN:+$EXCLUDE_PATTERN|}${arg#*=}" ;;
    --branch=*)    BRANCH_NAME="${arg#*=}" ;;
    -h|--help)
      sed -n '2,/^[^#]/{ /^#/s/^# \?//p }' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKFLOW_SRC="${SCRIPT_DIR}/../.github/workflows/pr-pii-check.yml"

if [[ ! -f "$WORKFLOW_SRC" ]]; then
  echo "ERROR: Workflow file not found at ${WORKFLOW_SRC}" >&2
  exit 1
fi

LOGDIR="./deploy-logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/deploy-pii-check-$(date +%Y%m%d-%H%M%S).log"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOGFILE"; }

log "Fetching repos from ${ORG}..."
REPOS=()
page=1
while true; do
  repos=$(gh api "orgs/${ORG}/repos?per_page=100&page=${page}&type=all" \
    --jq '.[].name' 2>/dev/null) || break
  [[ -z "$repos" ]] && break
  while IFS= read -r r; do REPOS+=("$r"); done <<< "$repos"
  page=$((page + 1))
done
log "Found ${#REPOS[@]} repos"

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

deployed=0 skipped=0 failed=0

for repo_name in "${REPOS[@]}"; do
  if is_filtered_out "$repo_name"; then
    log "SKIP (filter): ${repo_name}"
    skipped=$((skipped + 1))
    continue
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY RUN: Would deploy PII check to ${ORG}/${repo_name}"
    deployed=$((deployed + 1))
    continue
  fi

  log "Deploying to: ${ORG}/${repo_name}..."
  repo_dir="${WORK_DIR}/${repo_name}"
  default_branch=$(gh api "repos/${ORG}/${repo_name}" --jq '.default_branch' 2>/dev/null || echo "main")

  if ! git clone --depth 1 "https://github.com/${ORG}/${repo_name}.git" "$repo_dir" 2>>"$LOGFILE"; then
    log "FAIL (clone): ${repo_name}"
    failed=$((failed + 1))
    continue
  fi

  cd "$repo_dir"

  if [[ -f ".github/workflows/pr-pii-check.yml" ]]; then
    log "SKIP (exists): ${repo_name}"
    skipped=$((skipped + 1))
    cd - >/dev/null
    rm -rf "$repo_dir"
    continue
  fi

  git checkout -b "$BRANCH_NAME" 2>>"$LOGFILE"
  mkdir -p .github/workflows
  cp "$WORKFLOW_SRC" .github/workflows/pr-pii-check.yml
  git add .github/workflows/pr-pii-check.yml
  git commit -m "Add PR PII check workflow

Adds a GitHub Actions workflow that fails if PR descriptions or comments
contain 'Requested by' PII patterns. This enforces privacy in a
multi-tenant workshop environment." 2>>"$LOGFILE"

  if ! git push origin "$BRANCH_NAME" 2>>"$LOGFILE"; then
    log "FAIL (push): ${repo_name}"
    failed=$((failed + 1))
    cd - >/dev/null
    rm -rf "$repo_dir"
    continue
  fi

  pr_url=$(gh pr create \
    --repo "${ORG}/${repo_name}" \
    --base "$default_branch" \
    --head "$BRANCH_NAME" \
    --title "Add PR PII check workflow" \
    --body "Adds a GitHub Actions workflow that checks PR descriptions and comments for 'Requested by' PII patterns and fails the CI check if found.

After merging, enable branch protection on \`${default_branch}\` and require the **PR PII Check** status check to pass." 2>>"$LOGFILE" || echo "")

  if [[ -n "$pr_url" ]]; then
    log "OK: ${repo_name} -> ${pr_url}"
    deployed=$((deployed + 1))
  else
    log "FAIL (pr): ${repo_name}"
    failed=$((failed + 1))
  fi

  cd - >/dev/null
  rm -rf "$repo_dir"
  sleep 0.5
done

log ""
log "=== Deploy Summary ==="
log "Deployed: ${deployed} | Skipped: ${skipped} | Failed: ${failed}"
log "Log: ${LOGFILE}"
log ""
log "Next: Enable branch protection on each repo to require the 'PR PII Check' status check."
