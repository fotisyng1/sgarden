#!/usr/bin/env bash
# tests/stock_tests.sh – stock management tests.
#
# Tests cover:
#   - GET /api/products/:id   includes stock field
#   - PATCH /api/products/:id/stock  set / reject negative
#   - POST /api/orders        deducts stock / rejects on insufficient stock
#   - POST /api/products      accepts stock on creation
#
# Requires: helpers.sh sourced, _AUTH_TOKEN set by acquire_token.

# Product resolved once for the whole suite.
_STOCK_PRODUCT_ID=""

_resolve_stock_product() {
  local resp
  # Sort by stock desc so we land on a well-stocked seed product.
  resp=$(curl -s "${BASE_URL}/api/products?limit=1&sort=stock&order=desc")
  _STOCK_PRODUCT_ID=$(echo "$resp" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
print(data['data'][0]['id'])
")
  if [[ -z "$_STOCK_PRODUCT_ID" ]]; then
    echo "ERROR: could not resolve a product for stock tests" >&2
    return 1
  fi
}

# ── Helpers ───────────────────────────────────────────────────────────────────

# Set stock to a known value and fail loudly if it doesn't work.
_set_stock() {
  local qty="$1"
  local resp status
  resp=$(json_patch "/api/products/${_STOCK_PRODUCT_ID}/stock" "{\"stock\":${qty}}")
  status=$(tail -1 <<< "$resp")
  if [[ "$status" -ne 200 ]]; then
    echo "ERROR: could not set stock to ${qty}, got HTTP ${status}" >&2
    return 1
  fi
}

# Return current stock for _STOCK_PRODUCT_ID as a plain integer.
_get_current_stock() {
  curl -s "${BASE_URL}/api/products/${_STOCK_PRODUCT_ID}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('stock',0))"
}

# ── Test functions ────────────────────────────────────────────────────────────

t_stock_field_exists() {
  local body
  body=$(curl -s "${BASE_URL}/api/products/${_STOCK_PRODUCT_ID}")
  py "
import json
p = json.loads('''$body''')
assert 'stock' in p, 'product is missing the stock field'
assert isinstance(p['stock'], int), f'stock must be int, got {type(p[\"stock\"]).__name__}'
"
}

t_stock_patch_set() {
  local resp status body
  resp=$(json_patch "/api/products/${_STOCK_PRODUCT_ID}/stock" '{"stock":75}')
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status; body: $body"; return 1; }
  py "
import json
p = json.loads('''$body''')
assert p.get('stock') == 75, f'Expected stock=75, got {p.get(\"stock\")}'
assert 'id' in p, 'response should include full product object'
"
}

t_stock_patch_negative() {
  local resp status body
  resp=$(json_patch "/api/products/${_STOCK_PRODUCT_ID}/stock" '{"stock":-10}')
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 400 ]] || { echo "Expected 400, got $status; body: $body"; return 1; }
  py "
import json
b = json.loads('''$body''')
assert 'errors' in b, f'expected errors object in: {b}'
assert 'stock' in b['errors'], f'expected errors.stock in: {b[\"errors\"]}'
"
}

t_stock_order_deduction() {
  # Set a known stock level, place an order, verify stock decreased.
  _set_stock 10 || return 1

  local resp status body order_id
  resp=$(json_post "/api/orders" \
    "{\"items\":[{\"productId\":\"${_STOCK_PRODUCT_ID}\",\"quantity\":3}]}")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 201 ]] || { echo "Order failed: $status; body: $body"; return 1; }

  order_id=$(py "import json; print(json.loads('''$body''')['id'])")
  [[ -n "$order_id" ]] && _CREATED_ORDER_IDS+=("$order_id")

  local new_stock
  new_stock=$(_get_current_stock)
  [[ "$new_stock" -eq 7 ]] || { echo "Expected stock=7 after ordering 3 from 10, got $new_stock"; return 1; }
}

t_stock_insufficient_returns_400() {
  # Set stock to 5, try to order 10 – must be rejected with 400.
  _set_stock 5 || return 1

  local resp status body
  resp=$(json_post "/api/orders" \
    "{\"items\":[{\"productId\":\"${_STOCK_PRODUCT_ID}\",\"quantity\":10}]}")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 400 ]] || { echo "Expected 400, got $status; body: $body"; return 1; }
}

t_stock_unchanged_after_rejection() {
  # Immediately after t_stock_insufficient_returns_400, stock must still be 5.
  local stock
  stock=$(_get_current_stock)
  [[ "$stock" -eq 5 ]] || { echo "Expected stock=5 (unchanged after rejection), got $stock"; return 1; }
}

t_stock_set_on_create() {
  local resp status body created_id
  resp=$(json_post "/api/products" \
    '{"name":"__stock_create_test__","price":2.49,"category":"Storage","stock":7}')
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 201 ]] || { echo "Expected 201, got $status; body: $body"; return 1; }
  py "
import json
p = json.loads('''$body''')
assert p.get('stock') == 7, f'Expected stock=7 on created product, got {p.get(\"stock\")}'
"
  created_id=$(py "import json; print(json.loads('''$body''')['id'])")
  [[ -n "$created_id" ]] && _CREATED_PRODUCT_IDS+=("$created_id")
}

t_stock_patch_unauthenticated() {
  local resp status
  # Use a raw curl without any Authorization header.
  resp=$(curl -s -w "\n%{http_code}" \
    -X PATCH "${BASE_URL}/api/products/${_STOCK_PRODUCT_ID}/stock" \
    -H "Content-Type: application/json" \
    -d '{"stock":10}')
  status=$(tail -1 <<< "$resp")
  [[ "$status" -eq 401 || "$status" -eq 403 ]] || \
    { echo "Expected 401 or 403, got $status"; return 1; }
}

# ── Suite entry point ─────────────────────────────────────────────────────────

run_stock_tests() {
  echo -e "${BOLD}── Stock Management  PATCH /api/products/:id/stock ───────────────────${RESET}"
  _resolve_stock_product || { echo "  Skipping stock tests – no products available"; return; }
  run_test        "GET /:id includes stock as a number"                          t_stock_field_exists
  run_test        "PATCH /:id/stock {stock:75} → 200, stock updated to 75"      t_stock_patch_set
  run_test        "PATCH /:id/stock {stock:-10} → 400 with errors.stock"        t_stock_patch_negative
  run_test_direct "POST /orders deducts stock by ordered quantity"               t_stock_order_deduction
  run_test_direct "POST /orders with qty > stock → 400"                         t_stock_insufficient_returns_400
  run_test        "stock unchanged after rejected order"                         t_stock_unchanged_after_rejection
  run_test_direct "POST /products with stock field sets it correctly"            t_stock_set_on_create
  run_test        "PATCH /:id/stock without auth → 401 or 403"                  t_stock_patch_unauthenticated
}



