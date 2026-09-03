#!/usr/bin/env bash
# verify-auth.sh — Verify API authentication and display enterprise state
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/manage-org.sh"
source "${SCRIPT_DIR}/lib/manage-repos.sh"

echo "============================================"
echo "  Devin Enterprise — Auth Verification"
echo "============================================"
echo

# Step 1: Verify identity
info "Verifying API credentials..."
self_json=$(api_get "/v3/self")
principal_type=$(echo "$self_json" | jq -r '.principal_type')
su_id=$(echo "$self_json" | jq -r '.service_user_id // empty')
su_name=$(echo "$self_json" | jq -r '.service_user_name // empty')
org_id=$(echo "$self_json" | jq -r '.org_id // "enterprise-scoped"')

echo
echo "  Principal type : ${principal_type}"
echo "  Service user   : ${su_name} (${su_id})"
echo "  Scope          : ${org_id}"
echo

if [[ "$principal_type" != "service_user" ]]; then
  die "Expected principal_type=service_user, got ${principal_type}. Ensure DEVIN_API_KEY is a service user key."
fi

# Step 2: List organizations
info "Listing organizations..."
orgs_json=$(api_get "/v3/enterprise/organizations")
org_count=$(echo "$orgs_json" | jq '.total')
echo
echo "  Organizations (${org_count}):"
echo "$orgs_json" | jq -r '.items[] | "    \(.org_id)  \(.name)  (session=\(.max_session_acu_limit // "null"), cycle=\(.max_cycle_acu_limit // "null"))"'
echo

# Step 3: List git connections
info "Listing git connections..."
connections_json=$(list_git_connections)
echo
echo "  Git connections:"
echo "$connections_json" | jq -r '.[] | "    \(.git_connection_id)  \(.git_provider_type)  \(.name)  (\(.host))"'
echo

# Step 4: List enterprise members
info "Listing enterprise members..."
members_json=$(list_enterprise_members)
echo
echo "  Enterprise members:"
echo "$members_json" | jq -r '.[] | "    \(.user_id)  \(.email)  \(.name)"'
echo

# Step 5: List service users
info "Listing service users..."
sus_json=$(list_service_users)
echo
echo "  Service users:"
echo "$sus_json" | jq -r '.[] | "    \(.service_user_id)  \(.name)  (expires: \(.expires_at // "never"))"'
echo

# Step 6: List enterprise roles
info "Listing enterprise roles..."
roles_json=$(api_get "/v3/enterprise/roles") || true
if [[ -n "$roles_json" ]]; then
  echo
  echo "  Enterprise roles:"
  echo "$roles_json" | jq -r '.items[] | "    \(.role_id)  \(.role_name)  (\(.role_type))"' 2>/dev/null || echo "    (unable to parse roles response)"
  echo
else
  echo "  (no roles returned or endpoint unavailable)"
  echo
fi

echo "============================================"
echo "  Verification complete"
echo "============================================"
