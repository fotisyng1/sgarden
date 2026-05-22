#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# tests/helpers.sh – shared utilities for every test file.
#
# Sourced by test.sh.  Relies on the following variables being set in the
# calling script BEFORE sourcing this file:
#
#   BASE_URL            e.g. http://localhost:4000
#   PASS / FAIL         integer counters (initialised to 0)
#   RESULTS             array of result strings
#   _AUTH_TOKEN         JWT token (populated by acquire_token)
#   _CREATED_PRODUCT_IDS  array of product IDs to delete on cleanup
#   _CREATED_ORDER_IDS    array of order IDs to delete on cleanup
# ---------------------------------------------------------------------------

# ── ANSI colours ─────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── HTTP helpers ──────────────────────────────────────────────────────────────

# json_get <path> [query-string]
# Outputs: <body>\n<status_code>
json_get() {
  local url="${BASE_URL}${1}"
  [[ -n "${2:-}" ]] && url="${url}?${2}"
  curl -s -w "\n%{http_code}" "$url"
}

# json_post <path> <json-body>  – authenticated
json_post() {
  curl -s -w "\n%{http_code}" \
    -X POST "${BASE_URL}${1}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${_AUTH_TOKEN}" \
    -d "$2"
}

# json_post_anon <path> <json-body>  – unauthenticated (no auth header)
json_post_anon() {
  curl -s -w "\n%{http_code}" \
    -X POST "${BASE_URL}${1}" \
    -H "Content-Type: application/json" \
    -d "$2"
}

# json_put <path> <json-body>  – authenticated
json_put() {
  curl -s -w "\n%{http_code}" \
    -X PUT "${BASE_URL}${1}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${_AUTH_TOKEN}" \
    -d "$2"
}

# json_delete <path>  – authenticated
json_delete() {
  curl -s -w "\n%{http_code}" \
    -X DELETE "${BASE_URL}${1}" \
    -H "Authorization: Bearer ${_AUTH_TOKEN}"
}

# json_patch <path> <json-body>  – authenticated
json_patch() {
  curl -s -w "\n%{http_code}" \
    -X PATCH "${BASE_URL}${1}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${_AUTH_TOKEN}" \
    -d "$2"
}

# ── Test runner ───────────────────────────────────────────────────────────────

# record <name> <0=pass|1=fail> [reason]
record() {
  local name="$1" ok="$2" reason="${3:-}"
  if [[ "$ok" -eq 0 ]]; then
    RESULTS+=("${GREEN}✅ PASS${RESET}  $name")
    PASS=$(( PASS + 1 ))
  else
    RESULTS+=("${RED}❌ FAIL${RESET}  $name${reason:+$'\n'         ↳ $reason}")
    FAIL=$(( FAIL + 1 ))
  fi
}

# run_test <name> <function>
# Runs function in a subshell to capture output.  Variable assignments inside
# the function do NOT propagate to the caller.
run_test() {
  local name="$1"; shift
  local output
  if output=$("$@" 2>&1); then
    record "$name" 0
  else
    record "$name" 1 "$output"
  fi
}

# run_test_direct <name> <function>
# Runs function in the CURRENT shell so that variable assignments propagate.
# stderr/stdout are captured via a temp file and shown on failure.
run_test_direct() {
  local name="$1"; shift
  local tmpfile
  tmpfile=$(mktemp)
  if "$@" > "$tmpfile" 2>&1; then
    record "$name" 0
  else
    record "$name" 1 "$(cat "$tmpfile")"
  fi
  rm -f "$tmpfile"
}

# ── Inline Python helper ──────────────────────────────────────────────────────
py() { python3 -c "$1"; }

# ── Auth ──────────────────────────────────────────────────────────────────────

# acquire_token – logs in as the seeded admin, stores JWT in _AUTH_TOKEN.
acquire_token() {
  _AUTH_TOKEN=$(curl -s -X POST "${BASE_URL}/api/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"admin123"}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))")
  if [[ -z "$_AUTH_TOKEN" ]]; then
    echo -e "${RED}ERROR: could not acquire auth token${RESET}" >&2
    exit 1
  fi
}

# ── Cleanup ───────────────────────────────────────────────────────────────────

# cleanup_created – delete any resources created during the test run
cleanup_created() {
  for id in "${_CREATED_PRODUCT_IDS[@]}"; do
    json_delete "/api/products/${id}" > /dev/null
  done
  for id in "${_CREATED_ORDER_IDS[@]}"; do
    json_delete "/api/orders/${id}" > /dev/null
  done
}




