# Devin v3 API Reference Cheatsheet

Quick reference for all API endpoints used by the operator scripts. Full docs: https://docs.devin.ai/api-reference/overview

## Base URLs

| Scope | Base URL |
|---|---|
| Enterprise | `https://api.devin.ai/v3/enterprise/*` |
| Organization | `https://api.devin.ai/v3/organizations/{org_id}/*` |

All requests require `Authorization: Bearer cog_...` header.

---

## Identity & Self

### Verify credentials
```
GET /v3/self
```
Returns: `{principal_type, service_user_id, service_user_name, org_id}`

Enterprise service users have `org_id: null`.

---

## Organizations

### List organizations
```
GET /v3/enterprise/organizations
```
Returns paginated list of orgs with `{org_id, name, max_session_acu_limit, max_cycle_acu_limit}`.

### Create organization
```
POST /v3/enterprise/organizations
```
Body:
```json
{
  "name": "Workshop-Name",
  "max_session_acu_limit": 250,
  "max_cycle_acu_limit": 250
}
```
**Important:** `max_cycle_acu_limit` must be > 0 or sessions will be suspended with `org_usage_limit_exceeded`.

### Update organization
```
PATCH /v3/enterprise/organizations/{org_id}
```
Body: `{name?, max_session_acu_limit?, max_cycle_acu_limit?}` — all fields optional.

### Delete organization
```
DELETE /v3/enterprise/organizations/{org_id}
```

---

## Git Connections

### List git connections
```
GET /v3/enterprise/git-providers/connections
```
Returns: `{git_connection_id, git_provider_type, name, host}`

The `git_connection_id` is needed for all permission operations. For the mirror org, this is the GitHub App connection for `Cognition-Partner-Workshops-mirror`.

---

## Git Permissions

Permissions are per-org and reference repos via the org-wide git connection.

### List permissions
```
GET /v3/enterprise/organizations/{org_id}/git-providers/permissions
```

### Create permissions (additive)
```
POST /v3/enterprise/organizations/{org_id}/git-providers/permissions
```
Body:
```json
{
  "permissions": [
    {"git_connection_id": "git-connection-xxx", "repo_path": "Org/repo-name"},
    {"git_connection_id": "git-connection-xxx", "repo_path": "Org/another-repo"}
  ]
}
```
Max 200 permissions per request.

### Replace permissions (idempotent)
```
PUT /v3/enterprise/organizations/{org_id}/git-providers/permissions
```
Same body format as POST. Replaces all existing permissions with exactly the provided set. Preferred for reproducible provisioning.

### Delete single permission
```
DELETE /v3/enterprise/organizations/{org_id}/git-providers/permissions/{git_permission_id}
```

### Clear all permissions
```
DELETE /v3/enterprise/organizations/{org_id}/git-providers/permissions
```

---

## Sessions

### Create session
```
POST /v3/organizations/{org_id}/sessions
```
Body:
```json
{
  "prompt": "Your task description",
  "create_as_user_id": "google-oauth2|...",
  "repos": ["Org/repo-name"],
  "playbook_id": "playbook-xxx",
  "tags": ["setup"],
  "max_acu_limit": 50
}
```
Only `prompt` is required. `create_as_user_id` requires the `ImpersonateOrgSessions` permission and the target user must be an org member.

### Get session
```
GET /v3/organizations/{org_id}/sessions/{session_id}
```
Returns: `{session_id, url, status, status_detail, acus_consumed, pull_requests, ...}`

Status values: `new` → `claimed` → `running` → `suspended` / `exit` / `error`

### List sessions
```
GET /v3/organizations/{org_id}/sessions
```

---

## Members

### List enterprise members
```
GET /v3/enterprise/members/users
```

### List org members
```
GET /v3/enterprise/organizations/{org_id}/members/users
```

### List service users
```
GET /v3/enterprise/members/service-users
```

---

## Permissions Reference

| Permission | Scope | Grants |
|---|---|---|
| `ManageOrganizations` | Enterprise | Create/update/delete orgs |
| `ManageGitIntegrations` | Enterprise | Manage git connections and permissions |
| `ManageOrgSessions` | Org | Create/list sessions |
| `ImpersonateOrgSessions` | Org | Create sessions as another user |
| `UseDevinSessions` | Org | Required for target user of `create_as_user_id` |
| `ViewAccountMetrics` | Enterprise | Read consumption and metrics |
| `ViewAccountAuditLogs` | Enterprise | Read audit logs |

Enterprise admin service users inherit all org-level permissions across all organizations.
