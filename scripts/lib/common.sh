#!/usr/bin/env bash
# common.sh — Shared functions for Devin v3 API operator scripts
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
API_BASE="${DEVIN_API_BASE:-https://api.devin.ai}"
DEVIN_API_KEY="${DEVIN_API_KEY:?DEVIN_API_KEY must be set to a cog_ enterprise service user key}"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log()  { echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*" >&2; }
info() { log "INFO  $*"; }
warn() { log "WARN  $*" >&2; }
err()  { log "ERROR $*" >&2; }
die()  { err "$@"; exit 1; }

# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

# Generic GET request. Returns JSON body, dies on HTTP error.
api_get() {
  local url="$1"
  local response
  response=$(curl -sS -w '\n%{http_code}' \
    -H "Authorization: Bearer ${DEVIN_API_KEY}" \
    -H "Accept: application/json" \
    "${API_BASE}${url}" 2>&1) || true

  local http_code body
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
    echo "$body"
  else
    err "GET ${url} returned HTTP ${http_code}"
    err "Response: ${body}"
    return 1
  fi
}

# Generic POST request. Takes URL and JSON body. Returns JSON body.
api_post() {
  local url="$1"
  local data="$2"
  local response
  response=$(curl -sS -w '\n%{http_code}' \
    -X POST \
    -H "Authorization: Bearer ${DEVIN_API_KEY}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "$data" \
    "${API_BASE}${url}" 2>&1) || true

  local http_code body
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
    echo "$body"
  else
    err "POST ${url} returned HTTP ${http_code}"
    err "Response: ${body}"
    return 1
  fi
}

# Generic PATCH request.
api_patch() {
  local url="$1"
  local data="$2"
  local response
  response=$(curl -sS -w '\n%{http_code}' \
    -X PATCH \
    -H "Authorization: Bearer ${DEVIN_API_KEY}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "$data" \
    "${API_BASE}${url}" 2>&1) || true

  local http_code body
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
    echo "$body"
  else
    err "PATCH ${url} returned HTTP ${http_code}"
    err "Response: ${body}"
    return 1
  fi
}

# Generic PUT request.
api_put() {
  local url="$1"
  local data="$2"
  local response
  response=$(curl -sS -w '\n%{http_code}' \
    -X PUT \
    -H "Authorization: Bearer ${DEVIN_API_KEY}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "$data" \
    "${API_BASE}${url}" 2>&1) || true

  local http_code body
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
    echo "$body"
  else
    err "PUT ${url} returned HTTP ${http_code}"
    err "Response: ${body}"
    return 1
  fi
}

# Generic DELETE request.
api_delete() {
  local url="$1"
  local response
  response=$(curl -sS -w '\n%{http_code}' \
    -X DELETE \
    -H "Authorization: Bearer ${DEVIN_API_KEY}" \
    -H "Accept: application/json" \
    "${API_BASE}${url}" 2>&1) || true

  local http_code body
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
    echo "$body"
  else
    err "DELETE ${url} returned HTTP ${http_code}"
    err "Response: ${body}"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Config helpers
# ---------------------------------------------------------------------------

# Read a field from a JSON config file.
# Usage: config_get <file> <jq_expression>
config_get() {
  local file="$1" expr="$2"
  jq -r "$expr" "$file"
}

# Read an array from a JSON config as newline-delimited values.
config_get_array() {
  local file="$1" expr="$2"
  jq -r "${expr}[]" "$file"
}
