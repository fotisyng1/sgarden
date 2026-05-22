#!/usr/bin/env bash
# tests/alerts_tests.sh – tests for /api/alerts (Mission 7).
#
# Tests cover:
#   - GET /api/alerts returns 200 with array
#   - Products below threshold appear in alerts
#   - PUT /api/alerts/threshold sets threshold
#   - Each alert has severity field (critical, warning, or info)
#   - Products above threshold are excluded
#   - Each alert has product name and stock
#   - GET /api/alerts without auth returns 401 or 403
#
# Requires: helpers.sh sourced, _AUTH_TOKEN set by acquire_token.

# ── Test functions ────────────────────────────────────────────────────────────

t_alerts_get_returns_array() {
  local resp status body
  resp=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer ${_AUTH_TOKEN}" \
    "${BASE_URL}/api/alerts")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
alerts = json.loads('''$body''')
assert isinstance(alerts, list), f'expected array, got {type(alerts).__name__}'
"
}

t_alerts_set_threshold() {
  local resp status body
  resp=$(json_put "/api/alerts/threshold" '{"threshold":25}')
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status; body: $body"; return 1; }
  py "
import json
r = json.loads('''$body''')
assert r.get('threshold') == 25, f'Expected threshold=25, got {r.get(\"threshold\")}'
"
}

t_alerts_below_threshold_appear() {
  # Set threshold high enough that some seeded products appear
  json_put "/api/alerts/threshold" '{"threshold":100}' > /dev/null
  local resp status body
  resp=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer ${_AUTH_TOKEN}" \
    "${BASE_URL}/api/alerts")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
alerts = json.loads('''$body''')
assert len(alerts) > 0, 'Expected at least one alert when threshold is 100'
for a in alerts:
    assert a['stock'] < 100, f'Alert product stock {a[\"stock\"]} should be below threshold 100'
"
}

t_alerts_severity_field() {
  local resp body
  resp=$(curl -s \
    -H "Authorization: Bearer ${_AUTH_TOKEN}" \
    "${BASE_URL}/api/alerts")
  py "
import json
alerts = json.loads('''$resp''')
valid = {'critical', 'warning', 'info'}
for a in alerts:
    assert 'severity' in a, f'alert missing severity field: {a}'
    assert a['severity'] in valid, f'invalid severity {a[\"severity\"]}, expected one of {valid}'
"
}

t_alerts_above_threshold_excluded() {
  # Set a low threshold so most products are above it
  json_put "/api/alerts/threshold" '{"threshold":2}' > /dev/null
  local resp body
  resp=$(curl -s \
    -H "Authorization: Bearer ${_AUTH_TOKEN}" \
    "${BASE_URL}/api/alerts")
  py "
import json
alerts = json.loads('''$resp''')
for a in alerts:
    assert a['stock'] < 2, f'Product with stock {a[\"stock\"]} should not appear with threshold 2'
"
}

t_alerts_contain_name_and_stock() {
  json_put "/api/alerts/threshold" '{"threshold":100}' > /dev/null
  local resp body
  resp=$(curl -s \
    -H "Authorization: Bearer ${_AUTH_TOKEN}" \
    "${BASE_URL}/api/alerts")
  py "
import json
alerts = json.loads('''$resp''')
assert len(alerts) > 0, 'Need at least one alert to verify fields'
for a in alerts:
    assert 'name' in a and a['name'], f'alert missing name: {a}'
    assert 'stock' in a and isinstance(a['stock'], int), f'alert missing/invalid stock: {a}'
"
}

t_alerts_unauthenticated() {
  local resp status
  resp=$(curl -s -w "\n%{http_code}" \
    "${BASE_URL}/api/alerts")
  status=$(tail -1 <<< "$resp")
  [[ "$status" -eq 401 || "$status" -eq 403 ]] || \
    { echo "Expected 401 or 403, got $status"; return 1; }
}

# ── Suite entry point ─────────────────────────────────────────────────────────

run_alerts_tests() {
  echo -e "${BOLD}── Alerts  /api/alerts ───────────────────────────────────────────────${RESET}"
  run_test "GET /api/alerts → 200 with array"                               t_alerts_get_returns_array
  run_test "PUT /api/alerts/threshold {threshold:25} → 200 with value 25"   t_alerts_set_threshold
  run_test "Products below threshold appear in alerts"                       t_alerts_below_threshold_appear
  run_test "Each alert has severity: critical, warning, or info"             t_alerts_severity_field
  run_test "Products above threshold are excluded"                           t_alerts_above_threshold_excluded
  run_test "Each alert contains product name and stock"                      t_alerts_contain_name_and_stock
  run_test "GET /api/alerts without auth → 401 or 403"                      t_alerts_unauthenticated
}

