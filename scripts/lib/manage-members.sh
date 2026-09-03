#!/usr/bin/env bash
# manage-members.sh — Member invitation and management functions
# Source common.sh before using these functions.

# ---------------------------------------------------------------------------
# Invite users to the enterprise by email (batch).
# Usage: invite_enterprise_members <emails_json_array> [enterprise_role_id]
#
# emails_json_array: a jq-formatted JSON array of emails, e.g. '["a@b.com"]'
# Returns the API response (array of user objects with user_id).
# ---------------------------------------------------------------------------
invite_enterprise_members() {
  local emails_json="$1"
  local role_id="${2:-}"

  # enterprise_role_id is required by the API in most configurations.
  # If not provided, try to auto-discover a default member role.
  if [[ -z "$role_id" ]]; then
    info "No enterprise_role_id configured. Discovering available roles..."
    role_id=$(discover_default_enterprise_role) || true
    if [[ -n "$role_id" ]]; then
      info "Using discovered role: ${role_id}"
    else
      info "No roles found. Attempting invite without enterprise_role_id..."
    fi
  fi

  local payload
  if [[ -n "$role_id" ]]; then
    payload=$(jq -n --argjson emails "$emails_json" --arg role "$role_id" \
      '{emails: $emails, enterprise_role_id: $role}')
  else
    payload=$(jq -n --argjson emails "$emails_json" '{emails: $emails}')
  fi

  api_post "/v3/enterprise/members/users" "$payload"
}

# ---------------------------------------------------------------------------
# Discover the default enterprise member role.
# Returns the role_id of the first role found with "member" in the name
# (case-insensitive), or the first role if no "member" role exists.
# ---------------------------------------------------------------------------
discover_default_enterprise_role() {
  local roles_json
  roles_json=$(api_get "/v3/enterprise/roles") || return 1

  # Try to find a role with "member" in the name
  local role_id
  role_id=$(echo "$roles_json" | jq -r '
    [.items[] | select(.role_type == "enterprise") | select(.role_name | test("member"; "i"))] |
    if length > 0 then .[0].role_id
    else empty end' 2>/dev/null)

  if [[ -n "$role_id" ]]; then
    echo "$role_id"
    return 0
  fi

  # Fall back to first enterprise role
  role_id=$(echo "$roles_json" | jq -r '[.items[] | select(.role_type == "enterprise")][0].role_id // empty' 2>/dev/null)
  if [[ -n "$role_id" ]]; then
    echo "$role_id"
    return 0
  fi

  return 1
}

# ---------------------------------------------------------------------------
# Look up enterprise members by email.
# Usage: lookup_enterprise_member <email>
# Returns the user JSON object if found, empty string otherwise.
# ---------------------------------------------------------------------------
lookup_enterprise_member() {
  local email="$1"
  local members
  members=$(api_get "/v3/enterprise/members/users") || return 1
  echo "$members" | jq -r --arg e "$email" '.items[] | select(.email == $e)' 2>/dev/null
}

# ---------------------------------------------------------------------------
# Assign a user to an organization.
# Usage: assign_user_to_org <org_id> <user_id> [org_role_id]
# ---------------------------------------------------------------------------
assign_user_to_org() {
  local org_id="$1"
  local user_id="$2"
  local role_id="${3:-}"

  # role_id is required by the API. Default to org_member if not provided.
  if [[ -z "$role_id" ]]; then
    role_id="org_member"
  fi

  local payload
  payload=$(jq -n --arg r "$role_id" '{role_id: $r}')

  api_post "/v3/enterprise/organizations/${org_id}/members/users/${user_id}" "$payload"
}

# ---------------------------------------------------------------------------
# Invite a batch of emails and assign them to an org.
# Usage: invite_and_assign <org_id> <email1> [email2] ... [--enterprise-role=<id>] [--org-role=<id>]
#
# Handles batching (max 50 per API call) internally.
# Prints summary counts to stdout.
# ---------------------------------------------------------------------------
invite_and_assign() {
  local org_id="$1"
  shift

  local enterprise_role=""
  local org_role=""
  local emails=()

  for arg in "$@"; do
    case "$arg" in
      --enterprise-role=*) enterprise_role="${arg#*=}" ;;
      --org-role=*)        org_role="${arg#*=}" ;;
      *)                   emails+=("$arg") ;;
    esac
  done

  local invited=0 assigned=0 failed=0
  local batch_size=50

  for ((i = 0; i < ${#emails[@]}; i += batch_size)); do
    local batch=("${emails[@]:i:batch_size}")

    # Build JSON array
    local emails_json
    emails_json=$(printf '%s\n' "${batch[@]}" | jq -R . | jq -s .)

    info "Inviting ${#batch[@]} user(s) to enterprise..."
    local result user_ids="" lookup_failures=0
    if result=$(invite_enterprise_members "$emails_json" "$enterprise_role"); then
      user_ids=$(echo "$result" | jq -r '.[].user_id // empty' 2>/dev/null)
    else
      warn "Batch invite returned an error (users may already exist). Looking up individually..."
      for email in "${batch[@]}"; do
        local member_json
        member_json=$(lookup_enterprise_member "$email") || { lookup_failures=$((lookup_failures + 1)); continue; }
        local uid
        uid=$(echo "$member_json" | jq -r '.user_id // empty' 2>/dev/null)
        if [[ -n "$uid" ]]; then
          user_ids="${user_ids:+${user_ids}
}${uid}"
          info "Found existing user: ${email} -> ${uid}"
        else
          warn "Could not find user_id for ${email}"
          lookup_failures=$((lookup_failures + 1))
        fi
      done
      failed=$((failed + lookup_failures))
    fi

    if [[ -z "$user_ids" ]]; then
      if [[ "$lookup_failures" -eq 0 ]]; then
        failed=$((failed + ${#batch[@]}))
      fi
      warn "No user IDs resolved for batch. Skipping org assignment."
      continue
    fi

    invited=$((invited + $(echo "$user_ids" | wc -l)))

    while IFS= read -r user_id; do
      [[ -z "$user_id" ]] && continue

      local assign_result
      assign_result=$(assign_user_to_org "$org_id" "$user_id" "$org_role") || {
        warn "Failed to assign ${user_id} to org ${org_id}"
        failed=$((failed + 1))
        continue
      }

      if echo "$assign_result" | jq -e '.user_id' >/dev/null 2>&1; then
        assigned=$((assigned + 1))
      else
        warn "Unexpected response assigning ${user_id}: $(echo "$assign_result" | jq -c .)"
        failed=$((failed + 1))
      fi
    done <<< "$user_ids"

    sleep 0.5
  done

  echo "Invited: ${invited} | Assigned to org: ${assigned} | Failed: ${failed}"
}

# ---------------------------------------------------------------------------
# Read emails from a file (one per line, # comments, blank lines ignored).
# Usage: read_emails_file <file_path>
# Prints emails to stdout, one per line.
# ---------------------------------------------------------------------------
read_emails_file() {
  local file="$1"
  [[ ! -f "$file" ]] && { err "Emails file not found: ${file}"; return 1; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(echo "$line" | xargs)
    [[ -n "$line" ]] && [[ ! "$line" =~ ^# ]] && echo "$line"
  done < "$file"
}
