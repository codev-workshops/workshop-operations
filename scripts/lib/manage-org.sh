#!/usr/bin/env bash
# manage-org.sh — Organization lifecycle functions
# Source common.sh before using these functions.

# ---------------------------------------------------------------------------
# List all organizations in the enterprise.
# Prints JSON array of orgs.
# ---------------------------------------------------------------------------
list_orgs() {
  api_get "/v3/enterprise/organizations" | jq '.items'
}

# ---------------------------------------------------------------------------
# Get a single organization by ID.
# Usage: get_org <org_id>
# ---------------------------------------------------------------------------
get_org() {
  local org_id="$1"
  api_get "/v3/enterprise/organizations" | jq --arg id "$org_id" '.items[] | select(.org_id == $id)'
}

# ---------------------------------------------------------------------------
# Create a new organization.
# Usage: create_org <name> [max_session_acu_limit] [max_cycle_acu_limit]
# Returns the created org JSON.
# ---------------------------------------------------------------------------
create_org() {
  local name="$1"
  local max_session="${2:-250}"
  local max_cycle="${3:-250}"

  info "Creating organization: ${name} (session_limit=${max_session}, cycle_limit=${max_cycle})"
  local result
  result=$(api_post "/v3/enterprise/organizations" \
    "$(jq -n \
      --arg name "$name" \
      --argjson session "$max_session" \
      --argjson cycle "$max_cycle" \
      '{name: $name, max_session_acu_limit: $session, max_cycle_acu_limit: $cycle}')") || {
    die "Failed to create organization '${name}'. If it already exists, use --org-id <id> instead."
  }

  local org_id
  org_id=$(echo "$result" | jq -r '.org_id')
  if [[ -z "$org_id" || "$org_id" == "null" ]]; then
    die "API did not return an org_id. Response: ${result}"
  fi
  info "Created org: ${org_id} (${name})"
  echo "$result"
}

# ---------------------------------------------------------------------------
# Update an organization's name and/or ACU limits.
# Usage: update_org <org_id> [name] [max_session_acu_limit] [max_cycle_acu_limit]
# ---------------------------------------------------------------------------
update_org() {
  local org_id="$1"
  local name="${2:-}"
  local max_session="${3:-}"
  local max_cycle="${4:-}"

  local payload="{}"
  [[ -n "$name" ]] && payload=$(echo "$payload" | jq --arg n "$name" '. + {name: $n}')
  [[ -n "$max_session" ]] && payload=$(echo "$payload" | jq --argjson s "$max_session" '. + {max_session_acu_limit: $s}')
  [[ -n "$max_cycle" ]] && payload=$(echo "$payload" | jq --argjson c "$max_cycle" '. + {max_cycle_acu_limit: $c}')

  info "Updating org ${org_id}: ${payload}"
  api_patch "/v3/enterprise/organizations/${org_id}" "$payload"
}

# ---------------------------------------------------------------------------
# Delete an organization.
# Usage: delete_org <org_id>
# ---------------------------------------------------------------------------
delete_org() {
  local org_id="$1"
  warn "Deleting organization: ${org_id}"
  api_delete "/v3/enterprise/organizations/${org_id}"
  info "Deleted org: ${org_id}"
}

# ---------------------------------------------------------------------------
# List members of an organization.
# Usage: list_org_members <org_id>
# ---------------------------------------------------------------------------
list_org_members() {
  local org_id="$1"
  api_get "/v3/enterprise/organizations/${org_id}/members/users" | jq '.items'
}

# ---------------------------------------------------------------------------
# List all enterprise members.
# ---------------------------------------------------------------------------
list_enterprise_members() {
  api_get "/v3/enterprise/members/users" | jq '.items'
}

# ---------------------------------------------------------------------------
# List enterprise service users.
# ---------------------------------------------------------------------------
list_service_users() {
  api_get "/v3/enterprise/members/service-users" | jq '.items'
}
