#!/usr/bin/env bash
# tests/search_tests.sh – GET /api/products/search test suite.
# Sourced by test.sh; relies on helpers.sh being sourced first.

t_search_q_mouse() {
  local resp status body
  resp=$(json_get "/api/products/search" "q=mouse")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
products = json.loads('''$body''')
assert isinstance(products, list), 'body is not an array'
assert len(products) > 0, 'expected non-empty array for q=mouse'
for p in products:
    name = (p.get('name') or '').lower()
    desc = (p.get('description') or '').lower()
    assert 'mouse' in name or 'mouse' in desc, \
        f\"Product '{p.get('name')}' does not contain 'mouse'\"
"
}

t_search_category() {
  local resp status body
  resp=$(json_get "/api/products/search" "category=Electronics")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
products = json.loads('''$body''')
assert isinstance(products, list) and len(products) > 0
for p in products:
    assert p.get('category') == 'Electronics', \
        f\"Expected 'Electronics', got '{p.get('category')}'\"
"
}

t_search_min_price() {
  local resp status body
  resp=$(json_get "/api/products/search" "minPrice=50")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
products = json.loads('''$body''')
assert isinstance(products, list) and len(products) > 0
for p in products:
    assert (p.get('price') or 0) >= 50, \
        f\"Price {p.get('price')} < 50\"
"
}

t_search_max_price() {
  local resp status body
  resp=$(json_get "/api/products/search" "maxPrice=20")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
products = json.loads('''$body''')
assert isinstance(products, list) and len(products) > 0
for p in products:
    assert (p.get('price') or 0) <= 20, \
        f\"Price {p.get('price')} > 20\"
"
}

t_search_combined() {
  local resp status body
  resp=$(json_get "/api/products/search" "q=USB&minPrice=10&maxPrice=50")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
products = json.loads('''$body''')
assert isinstance(products, list) and len(products) > 0
for p in products:
    name = (p.get('name') or '').lower()
    desc = (p.get('description') or '').lower()
    assert 'usb' in name or 'usb' in desc
    price = p.get('price') or 0
    assert 10 <= price <= 50, f'Price {price} out of [10,50]'
"
}

t_search_no_results() {
  local resp status body
  resp=$(json_get "/api/products/search" "q=nonexistentxyz")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
products = json.loads('''$body''')
assert isinstance(products, list) and len(products) == 0, \
    f'Expected empty array, got {len(products)} items'
"
}

run_search_tests() {
  echo -e "${BOLD}── Search  GET /api/products/search ───────────────────────────────────${RESET}"
  run_test "q=mouse → text match in name/description"         t_search_q_mouse
  run_test "category=Electronics → exact category filter"     t_search_category
  run_test "minPrice=50 → price >= 50"                        t_search_min_price
  run_test "maxPrice=20 → price <= 20"                        t_search_max_price
  run_test "q=USB&minPrice=10&maxPrice=50 → combined filters" t_search_combined
  run_test "q=nonexistentxyz → empty array"                   t_search_no_results
}

