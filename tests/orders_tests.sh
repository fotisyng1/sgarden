#!/usr/bin/env bash
# tests/orders_tests.sh – full CRUD tests for /api/orders.
# Sourced by test.sh; relies on helpers.sh and an acquired _AUTH_TOKEN.

# Resolved at suite-setup time:
_ORDER_PRODUCT_ID=""
_ORDER_PRODUCT_PRICE=""
_TEST_ORDER_ID=""   # shared across dependent tests within this suite

# Pick a well-stocked seed product (stock >= 10) so test-created products
# with minimal stock (e.g. __test_product__ with stock=1) are never chosen.
_resolve_order_product() {
  local resp
  resp=$(curl -s "${BASE_URL}/api/products?limit=20&sort=stock&order=desc")
  _ORDER_PRODUCT_ID=$(echo "$resp" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
candidates = [p for p in data['data'] if (p.get('stock') or 0) >= 10]
if not candidates: sys.exit(1)
print(candidates[0]['id'])
")
  _ORDER_PRODUCT_PRICE=$(echo "$resp" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
candidates = [p for p in data['data'] if (p.get('stock') or 0) >= 10]
print(candidates[0]['price'])
")
  if [[ -z "$_ORDER_PRODUCT_ID" || -z "$_ORDER_PRODUCT_PRICE" ]]; then
    echo "ERROR: could not find a product with stock >= 10" >&2
    return 1
  fi
}

# ── Test functions ────────────────────────────────────────────────────────────

t_orders_create() {
  local resp status body
  resp=$(json_post "/api/orders" "{\"items\":[{\"productId\":\"${_ORDER_PRODUCT_ID}\",\"quantity\":2}]}")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 201 ]] || { echo "Expected 201, got $status; body: $body"; return 1; }
  py "
import json
o = json.loads('''$body''')
assert 'id' in o and o['id'], 'missing id'
assert 'items' in o and isinstance(o['items'], list), 'missing items array'
assert len(o['items']) == 1
assert 'total' in o, 'missing total'
"
  _TEST_ORDER_ID=$(py "import json; print(json.loads('''$body''')['id'])")
  [[ -n "$_TEST_ORDER_ID" ]] && _CREATED_ORDER_IDS+=("$_TEST_ORDER_ID")
}

t_orders_total_calculation() {
  [[ -n "$_TEST_ORDER_ID" ]] || { echo "skipped – depends on t_orders_create"; return 1; }
  local resp body
  resp=$(curl -s -H "Authorization: Bearer ${_AUTH_TOKEN}" "${BASE_URL}/api/orders/${_TEST_ORDER_ID}")
  py "
import json
o = json.loads('''$resp''')
expected = round(${_ORDER_PRODUCT_PRICE} * 2, 2)
assert abs(o['total'] - expected) < 0.01, \
    f'total {o[\"total\"]} != expected {expected}'
"
}

t_orders_list() {
  local resp status body
  resp=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer ${_AUTH_TOKEN}" "${BASE_URL}/api/orders")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
orders = json.loads('''$body''')
assert isinstance(orders, list), 'expected an array'
"
}

t_orders_get_one() {
  [[ -n "$_TEST_ORDER_ID" ]] || { echo "skipped – depends on t_orders_create"; return 1; }
  local resp status body
  resp=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer ${_AUTH_TOKEN}" \
    "${BASE_URL}/api/orders/${_TEST_ORDER_ID}")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
o = json.loads('''$body''')
assert o.get('id') == '${_TEST_ORDER_ID}', f'id mismatch: {o.get(\"id\")}'
assert 'items' in o and 'total' in o
"
}

t_orders_update() {
  [[ -n "$_TEST_ORDER_ID" ]] || { echo "skipped – depends on t_orders_create"; return 1; }
  local resp status body
  resp=$(json_put "/api/orders/${_TEST_ORDER_ID}" \
    "{\"items\":[{\"productId\":\"${_ORDER_PRODUCT_ID}\",\"quantity\":3}]}")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status; body: $body"; return 1; }
  py "
import json
o = json.loads('''$body''')
expected = round(${_ORDER_PRODUCT_PRICE} * 3, 2)
assert abs(o['total'] - expected) < 0.01, \
    f'total after update {o[\"total\"]} != expected {expected}'
assert o['items'][0]['quantity'] == 3
"
}

t_orders_delete() {
  [[ -n "$_TEST_ORDER_ID" ]] || { echo "skipped – depends on t_orders_create"; return 1; }
  local del_resp del_status get_status
  del_resp=$(json_delete "/api/orders/${_TEST_ORDER_ID}")
  del_status=$(tail -1 <<< "$del_resp")
  [[ "$del_status" -eq 200 ]] || { echo "DELETE expected 200, got $del_status"; return 1; }
  # Subsequent GET must return 404
  get_status=$(curl -s -w "%{http_code}" -o /dev/null \
    -H "Authorization: Bearer ${_AUTH_TOKEN}" \
    "${BASE_URL}/api/orders/${_TEST_ORDER_ID}")
  [[ "$get_status" -eq 404 ]] || { echo "Expected 404 after delete, got $get_status"; return 1; }
  # Remove from cleanup list – already deleted
  _CREATED_ORDER_IDS=("${_CREATED_ORDER_IDS[@]/$_TEST_ORDER_ID}")
  _TEST_ORDER_ID=""
}

t_orders_not_found() {
  local resp status
  resp=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer ${_AUTH_TOKEN}" \
    "${BASE_URL}/api/orders/000000000000000000000000")
  status=$(tail -1 <<< "$resp")
  [[ "$status" -eq 404 ]] || { echo "Expected 404, got $status"; return 1; }
}

t_orders_unauthenticated() {
  local resp status body
  resp=$(json_post_anon "/api/orders" \
    "{\"items\":[{\"productId\":\"${_ORDER_PRODUCT_ID}\",\"quantity\":1}]}")
  status=$(tail -1 <<< "$resp")
  [[ "$status" -eq 401 || "$status" -eq 403 ]] || \
    { echo "Expected 401/403, got $status"; return 1; }
}

# ── Suite entry point ─────────────────────────────────────────────────────────

run_orders_tests() {
  echo -e "${BOLD}── Orders  /api/orders ───────────────────────────────────────────────${RESET}"
  _resolve_order_product || { echo "  Skipping order tests – no products in catalogue"; return; }
  run_test_direct "POST with items → 201 with id and items"         t_orders_create
  run_test        "total == product price × quantity"               t_orders_total_calculation
  run_test        "GET / → 200 with array of orders"                t_orders_list
  run_test        "GET /:id → 200 with matching order"              t_orders_get_one
  run_test        "PUT /:id with new quantity → recalculated total" t_orders_update
  run_test_direct "DELETE /:id → 200; subsequent GET → 404"        t_orders_delete
  run_test        "GET /000000000000000000000000 → 404"             t_orders_not_found
  run_test        "POST without token → 401 or 403"                 t_orders_unauthenticated
}

