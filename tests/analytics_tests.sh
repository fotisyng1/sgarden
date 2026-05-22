#!/usr/bin/env bash
# tests/analytics_tests.sh – tests for /api/analytics/sales (Mission 9).
#
# Tests cover:
#   - GET /api/analytics/sales returns 200 with analytics object
#   - Response includes totalRevenue as number > 0
#   - Response includes totalOrders as number > 0
#   - Response includes topProducts as array with expected fields
#   - Response includes revenueByPeriod as array or object
#   - Date range filtering works
#   - Future date range returns zeros
#   - Unauthenticated returns 401 or 403
#
# Requires: helpers.sh sourced, _AUTH_TOKEN set by acquire_token.
# Note: These tests assume at least one order exists (created by orders_tests).

# ── Test functions ────────────────────────────────────────────────────────────

t_analytics_returns_object() {
  local resp status body
  resp=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer ${_AUTH_TOKEN}" \
    "${BASE_URL}/api/analytics/sales")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
data = json.loads('''$body''')
assert isinstance(data, dict), f'expected object, got {type(data).__name__}'
assert 'totalRevenue' in data, 'missing totalRevenue'
assert 'totalOrders' in data, 'missing totalOrders'
assert 'topProducts' in data, 'missing topProducts'
assert 'revenueByPeriod' in data, 'missing revenueByPeriod'
"
}

t_analytics_total_revenue_positive() {
  local resp body
  resp=$(curl -s \
    -H "Authorization: Bearer ${_AUTH_TOKEN}" \
    "${BASE_URL}/api/analytics/sales")
  py "
import json
data = json.loads('''$resp''')
assert isinstance(data['totalRevenue'], (int, float)), 'totalRevenue must be a number'
assert data['totalRevenue'] > 0, f'Expected totalRevenue > 0, got {data[\"totalRevenue\"]}'
"
}

t_analytics_total_orders_positive() {
  local resp body
  resp=$(curl -s \
    -H "Authorization: Bearer ${_AUTH_TOKEN}" \
    "${BASE_URL}/api/analytics/sales")
  py "
import json
data = json.loads('''$resp''')
assert isinstance(data['totalOrders'], (int, float)), 'totalOrders must be a number'
assert data['totalOrders'] > 0, f'Expected totalOrders > 0, got {data[\"totalOrders\"]}'
"
}

t_analytics_top_products() {
  local resp body
  resp=$(curl -s \
    -H "Authorization: Bearer ${_AUTH_TOKEN}" \
    "${BASE_URL}/api/analytics/sales")
  py "
import json
data = json.loads('''$resp''')
tp = data['topProducts']
assert isinstance(tp, list), f'topProducts must be array, got {type(tp).__name__}'
if len(tp) > 0:
    item = tp[0]
    assert 'productId' in item or 'name' in item, f'topProducts item missing productId/name: {item}'
    assert 'totalQuantity' in item or 'totalRevenue' in item, f'topProducts item missing quantity/revenue data: {item}'
"
}

t_analytics_revenue_by_period() {
  local resp body
  resp=$(curl -s \
    -H "Authorization: Bearer ${_AUTH_TOKEN}" \
    "${BASE_URL}/api/analytics/sales")
  py "
import json
data = json.loads('''$resp''')
rbp = data['revenueByPeriod']
assert isinstance(rbp, (list, dict)), f'revenueByPeriod must be array or object, got {type(rbp).__name__}'
"
}

t_analytics_date_range_filter() {
  local resp status body
  resp=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer ${_AUTH_TOKEN}" \
    "${BASE_URL}/api/analytics/sales?startDate=2024-01-01&endDate=2024-12-31")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
data = json.loads('''$body''')
assert 'totalRevenue' in data, 'missing totalRevenue in date-filtered response'
"
}

t_analytics_future_range_zeros() {
  local resp status body
  resp=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer ${_AUTH_TOKEN}" \
    "${BASE_URL}/api/analytics/sales?startDate=2099-01-01&endDate=2099-12-31")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
data = json.loads('''$body''')
assert data['totalRevenue'] == 0, f'Expected totalRevenue=0 for future range, got {data[\"totalRevenue\"]}'
assert data['totalOrders'] == 0, f'Expected totalOrders=0 for future range, got {data[\"totalOrders\"]}'
"
}

t_analytics_unauthenticated() {
  local resp status
  resp=$(curl -s -w "\n%{http_code}" \
    "${BASE_URL}/api/analytics/sales")
  status=$(tail -1 <<< "$resp")
  [[ "$status" -eq 401 || "$status" -eq 403 ]] || \
    { echo "Expected 401 or 403, got $status"; return 1; }
}

# ── Suite entry point ─────────────────────────────────────────────────────────

run_analytics_tests() {
  echo -e "${BOLD}── Analytics  /api/analytics/sales ──────────────────────────────────────${RESET}"
  run_test "GET /api/analytics/sales → 200 with analytics object"            t_analytics_returns_object
  run_test "totalRevenue is a number > 0"                                    t_analytics_total_revenue_positive
  run_test "totalOrders is a number > 0"                                     t_analytics_total_orders_positive
  run_test "topProducts is array with productId/name and quantity/revenue"   t_analytics_top_products
  run_test "revenueByPeriod is array or object"                              t_analytics_revenue_by_period
  run_test "Date range filter returns 200 with totalRevenue"                 t_analytics_date_range_filter
  run_test "Future date range returns totalRevenue=0 and totalOrders=0"      t_analytics_future_range_zeros
  run_test "GET /api/analytics/sales without auth → 401 or 403"             t_analytics_unauthenticated
}

