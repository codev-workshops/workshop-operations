#!/usr/bin/env bash
# manage-repos.sh — Git connection and permission management functions
# Source common.sh before using these functions.

# ---------------------------------------------------------------------------
# List all git connections (GitHub Apps, tokens, etc.) in the enterprise.
# ---------------------------------------------------------------------------
list_git_connections() {
  api_get "/v3/enterprise/git-providers/connections" | jq '.items'
}

# ---------------------------------------------------------------------------
# Find a git connection by name (e.g., "Cognition-Partner-Workshops-mirror").
# Usage: find_git_connection <name>
# Returns the connection JSON object, or empty if not found.
# ---------------------------------------------------------------------------
find_git_connection() {
  local name="$1"
  api_get "/v3/enterprise/git-providers/connections" | jq --arg n "$name" '.items[] | select(.name == $n)'
}

# ---------------------------------------------------------------------------
# List git permissions for an organization.
# Usage: list_git_permissions <org_id>
# ---------------------------------------------------------------------------
list_git_permissions() {
  local org_id="$1"
  api_get "/v3/enterprise/organizations/${org_id}/git-providers/permissions" | jq '.items'
}

# ---------------------------------------------------------------------------
# Add git permissions for repos to an organization (incremental).
# Usage: add_git_permissions <org_id> <git_connection_id> <repo1> [repo2] ...
#
# Each repo should be in "org/repo" format, e.g.:
#   add_git_permissions org-xxx git-connection-yyy "Org/repo1" "Org/repo2"
# ---------------------------------------------------------------------------
add_git_permissions() {
  local org_id="$1"
  local conn_id="$2"
  shift 2
  local repos=("$@")

  local permissions="[]"
  for repo in "${repos[@]}"; do
    permissions=$(echo "$permissions" | jq --arg c "$conn_id" --arg r "$repo" \
      '. + [{git_connection_id: $c, repo_path: $r}]')
  done

  local payload
  payload=$(jq -n --argjson p "$permissions" '{permissions: $p}')

  info "Adding ${#repos[@]} git permission(s) to org ${org_id}"
  api_post "/v3/enterprise/organizations/${org_id}/git-providers/permissions" "$payload"
}

# ---------------------------------------------------------------------------
# Replace all git permissions for an organization (idempotent).
# Usage: replace_git_permissions <org_id> <git_connection_id> <repo1> [repo2] ...
#
# This removes all existing permissions and sets exactly the repos provided.
# ---------------------------------------------------------------------------
replace_git_permissions() {
  local org_id="$1"
  local conn_id="$2"
  shift 2
  local repos=("$@")

  local permissions="[]"
  for repo in "${repos[@]}"; do
    permissions=$(echo "$permissions" | jq --arg c "$conn_id" --arg r "$repo" \
      '. + [{git_connection_id: $c, repo_path: $r}]')
  done

  local payload
  payload=$(jq -n --argjson p "$permissions" '{permissions: $p}')

  info "Replacing git permissions for org ${org_id} with ${#repos[@]} repo(s)"
  api_put "/v3/enterprise/organizations/${org_id}/git-providers/permissions" "$payload"
}

# ---------------------------------------------------------------------------
# Delete a single git permission by ID.
# Usage: delete_git_permission <org_id> <git_permission_id>
# ---------------------------------------------------------------------------
delete_git_permission() {
  local org_id="$1"
  local perm_id="$2"
  info "Deleting git permission ${perm_id} from org ${org_id}"
  api_delete "/v3/enterprise/organizations/${org_id}/git-providers/permissions/${perm_id}"
}

# ---------------------------------------------------------------------------
# Clear all git permissions from an organization.
# Usage: clear_git_permissions <org_id>
# ---------------------------------------------------------------------------
clear_git_permissions() {
  local org_id="$1"
  warn "Clearing ALL git permissions from org ${org_id}"
  api_delete "/v3/enterprise/organizations/${org_id}/git-providers/permissions"
  info "Cleared all git permissions from org ${org_id}"
}
