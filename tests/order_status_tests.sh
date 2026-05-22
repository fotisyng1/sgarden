#!/usr/bin/env bash
# tests/order_status_tests.sh – tests for order status state machine (Mission 8).
#
# Tests cover:
#   - New orders have status 'pending'
#   - PATCH /api/orders/:id/status transitions correctly
#   - Full workflow: pending -> confirmed -> shipped -> delivered
#   - Invalid transitions return 400
#   - Cancellation from pending allowed, from shipped rejected
#   - Delivered orders cannot change status
#   - GET /api/orders?status=pending filters correctly
#
# Requires: helpers.sh sourced, _AUTH_TOKEN set by acquire_token.

_STATUS_ORDER_ID=""
_STATUS_PRODUCT_ID=""

_resolve_status_product() {
  local resp
  resp=$(curl -s "${BASE_URL}/api/products?limit=20&sort=stock&order=desc")
  _STATUS_PRODUCT_ID=$(echo "$resp" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
candidates = [p for p in data['data'] if (p.get('stock') or 0) >= 10]
if not candidates: sys.exit(1)
print(candidates[0]['id'])
")
  if [[ -z "$_STATUS_PRODUCT_ID" ]]; then
    echo "ERROR: could not find a product with stock >= 10" >&2
    return 1
  fi
}

_create_status_order() {
  local resp status body
  resp=$(json_post "/api/orders" "{\"items\":[{\"productId\":\"${_STATUS_PRODUCT_ID}\",\"quantity\":1}]}")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  if [[ "$status" -ne 201 ]]; then
    echo "ERROR: could not create order for status tests, got $status" >&2
    return 1
  fi
  _STATUS_ORDER_ID=$(py "import json; print(json.loads('''$body''')['id'])")
  [[ -n "$_STATUS_ORDER_ID" ]] && _CREATED_ORDER_IDS+=("$_STATUS_ORDER_ID")
}

# ── Test functions ────────────────────────────────────────────────────────────

t_status_new_order_pending() {
  local resp status body order_id
  resp=$(json_post "/api/orders" "{\"items\":[{\"productId\":\"${_STATUS_PRODUCT_ID}\",\"quantity\":1}]}")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 201 ]] || { echo "Expected 201, got $status; body: $body"; return 1; }
  order_id=$(py "import json; print(json.loads('''$body''')['id'])")
  [[ -n "$order_id" ]] && _CREATED_ORDER_IDS+=("$order_id")
  py "
import json
o = json.loads('''$body''')
assert o.get('status') == 'pending', f'Expected status=pending, got {o.get(\"status\")}'
"
}

t_status_pending_to_confirmed() {
  [[ -n "$_STATUS_ORDER_ID" ]] || { echo "skipped – no order created"; return 1; }
  local resp status body
  resp=$(json_patch "/api/orders/${_STATUS_ORDER_ID}/status" '{"status":"confirmed"}')
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status; body: $body"; return 1; }
  py "
import json
o = json.loads('''$body''')
assert o.get('status') == 'confirmed', f'Expected confirmed, got {o.get(\"status\")}'
"
}

t_status_full_workflow() {
  # Create a fresh order and walk through pending -> confirmed -> shipped -> delivered
  local resp status body order_id
  resp=$(json_post "/api/orders" "{\"items\":[{\"productId\":\"${_STATUS_PRODUCT_ID}\",\"quantity\":1}]}")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 201 ]] || { echo "Create failed: $status"; return 1; }
  order_id=$(py "import json; print(json.loads('''$body''')['id'])")
  [[ -n "$order_id" ]] && _CREATED_ORDER_IDS+=("$order_id")

  for target in confirmed shipped delivered; do
    resp=$(json_patch "/api/orders/${order_id}/status" "{\"status\":\"${target}\"}")
    status=$(tail -1 <<< "$resp")
    [[ "$status" -eq 200 ]] || { echo "Transition to $target failed: $status"; return 1; }
  done
  body=$(head -n -1 <<< "$resp")
  py "
import json
o = json.loads('''$body''')
assert o.get('status') == 'delivered', f'Expected delivered, got {o.get(\"status\")}'
"
}

t_status_skip_step_returns_400() {
  # pending -> shipped should be invalid (skips confirmed)
  local resp status body order_id
  resp=$(json_post "/api/orders" "{\"items\":[{\"productId\":\"${_STATUS_PRODUCT_ID}\",\"quantity\":1}]}")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 201 ]] || { echo "Create failed: $status"; return 1; }
  order_id=$(py "import json; print(json.loads('''$body''')['id'])")
  [[ -n "$order_id" ]] && _CREATED_ORDER_IDS+=("$order_id")

  resp=$(json_patch "/api/orders/${order_id}/status" '{"status":"shipped"}')
  status=$(tail -1 <<< "$resp")
  [[ "$status" -eq 400 ]] || { echo "Expected 400 for pending->shipped, got $status"; return 1; }
}

t_status_cancel_pending() {
  local resp status body order_id
  resp=$(json_post "/api/orders" "{\"items\":[{\"productId\":\"${_STATUS_PRODUCT_ID}\",\"quantity\":1}]}")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 201 ]] || { echo "Create failed: $status"; return 1; }
  order_id=$(py "import json; print(json.loads('''$body''')['id'])")
  [[ -n "$order_id" ]] && _CREATED_ORDER_IDS+=("$order_id")

  resp=$(json_patch "/api/orders/${order_id}/status" '{"status":"cancelled"}')
  status=$(tail -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200 for pending->cancelled, got $status"; return 1; }
}

t_status_delivered_cannot_change() {
  # Create an order and transition to delivered
  local resp status body order_id
  resp=$(json_post "/api/orders" "{\"items\":[{\"productId\":\"${_STATUS_PRODUCT_ID}\",\"quantity\":1}]}")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 201 ]] || { echo "Create failed: $status"; return 1; }
  order_id=$(py "import json; print(json.loads('''$body''')['id'])")
  [[ -n "$order_id" ]] && _CREATED_ORDER_IDS+=("$order_id")

  for target in confirmed shipped delivered; do
    json_patch "/api/orders/${order_id}/status" "{\"status\":\"${target}\"}" > /dev/null
  done

  # Now try to change from delivered – must fail
  resp=$(json_patch "/api/orders/${order_id}/status" '{"status":"confirmed"}')
  status=$(tail -1 <<< "$resp")
  [[ "$status" -eq 400 ]] || { echo "Expected 400 for delivered->confirmed, got $status"; return 1; }
}

t_status_filter_by_status() {
  local resp status body
  resp=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer ${_AUTH_TOKEN}" \
    "${BASE_URL}/api/orders?status=pending")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
orders = json.loads('''$body''')
assert isinstance(orders, list), 'expected array'
for o in orders:
    assert o.get('status') == 'pending', f'Expected pending, got {o.get(\"status\")}'
"
}

t_status_cancel_shipped_returns_400() {
  # Create order, move to confirmed then shipped, then try to cancel
  local resp status body order_id
  resp=$(json_post "/api/orders" "{\"items\":[{\"productId\":\"${_STATUS_PRODUCT_ID}\",\"quantity\":1}]}")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 201 ]] || { echo "Create failed: $status"; return 1; }
  order_id=$(py "import json; print(json.loads('''$body''')['id'])")
  [[ -n "$order_id" ]] && _CREATED_ORDER_IDS+=("$order_id")

  json_patch "/api/orders/${order_id}/status" '{"status":"confirmed"}' > /dev/null
  json_patch "/api/orders/${order_id}/status" '{"status":"shipped"}' > /dev/null

  resp=$(json_patch "/api/orders/${order_id}/status" '{"status":"cancelled"}')
  status=$(tail -1 <<< "$resp")
  [[ "$status" -eq 400 ]] || { echo "Expected 400 for shipped->cancelled, got $status"; return 1; }
}

# ── Suite entry point ─────────────────────────────────────────────────────────

run_order_status_tests() {
  echo -e "${BOLD}── Order Status  PATCH /api/orders/:id/status ──────────────────────────${RESET}"
  _resolve_status_product || { echo "  Skipping order status tests – no products"; return; }
  _create_status_order || { echo "  Skipping order status tests – cannot create order"; return; }
  run_test_direct "New orders have status 'pending'"                          t_status_new_order_pending
  run_test        "PATCH status: pending → confirmed returns 200"             t_status_pending_to_confirmed
  run_test_direct "Full workflow: pending→confirmed→shipped→delivered"         t_status_full_workflow
  run_test_direct "Skipping step (pending→shipped) returns 400"               t_status_skip_step_returns_400
  run_test_direct "Cancel pending order returns 200"                          t_status_cancel_pending
  run_test_direct "Delivered order cannot change status → 400"                t_status_delivered_cannot_change
  run_test        "GET /api/orders?status=pending filters correctly"           t_status_filter_by_status
  run_test_direct "Cancel shipped order returns 400"                          t_status_cancel_shipped_returns_400
}

