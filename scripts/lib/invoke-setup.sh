#!/usr/bin/env bash
# invoke-setup.sh — Create Devin sessions to set up environment configs
# Source common.sh before using these functions.

# ---------------------------------------------------------------------------
# Create a single Devin session in an organization.
# Usage: create_session <org_id> <prompt> [create_as_user_id]
# Returns the session JSON response.
# ---------------------------------------------------------------------------
create_session() {
  local org_id="$1"
  local prompt="$2"
  local user_id="${3:-}"

  local payload
  if [[ -n "$user_id" ]]; then
    payload=$(jq -n --arg p "$prompt" --arg u "$user_id" \
      '{prompt: $p, create_as_user_id: $u}')
  else
    payload=$(jq -n --arg p "$prompt" '{prompt: $p}')
  fi

  api_post "/v3/organizations/${org_id}/sessions" "$payload"
}

# ---------------------------------------------------------------------------
# Get session status.
# Usage: get_session <org_id> <session_id>
# ---------------------------------------------------------------------------
get_session() {
  local org_id="$1"
  local session_id="$2"
  api_get "/v3/organizations/${org_id}/sessions/${session_id}"
}

# ---------------------------------------------------------------------------
# Poll session until it reaches a terminal state.
# Usage: poll_session <org_id> <session_id> [poll_interval_seconds]
# Returns 0 if session completed (exit), 1 if error/suspended.
# ---------------------------------------------------------------------------
poll_session() {
  local org_id="$1"
  local session_id="$2"
  local interval="${3:-30}"

  info "Polling session ${session_id} every ${interval}s..."
  while true; do
    local session_json status status_detail
    session_json=$(get_session "$org_id" "$session_id")
    status=$(echo "$session_json" | jq -r '.status')
    status_detail=$(echo "$session_json" | jq -r '.status_detail // empty')

    info "Session ${session_id}: status=${status}${status_detail:+ (${status_detail})}"

    case "$status" in
      exit)
        info "Session ${session_id} completed successfully"
        return 0
        ;;
      error|suspended)
        warn "Session ${session_id} ended with status=${status}${status_detail:+ (${status_detail})}"
        return 1
        ;;
      *)
        sleep "$interval"
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Create setup sessions for multiple repos.
# Usage: invoke_setup_sessions <org_id> <prompt_template> <user_id> <repo1> [repo2] ...
#
# The prompt_template should contain {repo} as a placeholder, e.g.:
#   "Set up the {repo} repository from scratch..."
#
# Returns a JSON array of {repo, session_id, url, status} objects.
# ---------------------------------------------------------------------------
invoke_setup_sessions() {
  local org_id="$1"
  local prompt_template="$2"
  local user_id="$3"
  shift 3
  local repos=("$@")

  local results="[]"

  for repo in "${repos[@]}"; do
    local prompt="${prompt_template//\{repo\}/$repo}"
    info "Creating setup session for ${repo}..."

    local session_json session_id url status
    session_json=$(create_session "$org_id" "$prompt" "$user_id") || {
      warn "Failed to create session for ${repo}"
      results=$(echo "$results" | jq --arg r "$repo" \
        '. + [{repo: $r, session_id: null, url: null, status: "failed_to_create"}]')
      continue
    }

    session_id=$(echo "$session_json" | jq -r '.session_id')
    url=$(echo "$session_json" | jq -r '.url')
    status=$(echo "$session_json" | jq -r '.status')

    info "  Session: ${session_id} (${url})"
    results=$(echo "$results" | jq \
      --arg r "$repo" --arg s "$session_id" --arg u "$url" --arg st "$status" \
      '. + [{repo: $r, session_id: $s, url: $u, status: $st}]')
  done

  echo "$results"
}
