#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# SGarden API – integration test suite
#
# Usage:
#   ./test.sh [BASE_URL]
#
# Defaults to http://localhost:4000 when BASE_URL is not provided.
#
# Exit codes:
#   0 – all tests passed
#   1 – one or more tests failed
# ---------------------------------------------------------------------------

BASE_URL="${1:-http://localhost:4000}"

PASS=0
FAIL=0
RESULTS=()
_AUTH_TOKEN=""
_CREATED_IDS=()  # IDs of products created during tests – cleaned up at exit

# ── colours ────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── helpers ────────────────────────────────────────────────────────────────

# json_get <path> [query-string]
# Performs a GET request and prints "<body>\n<status_code>" to stdout.
json_get() {
  local url="${BASE_URL}${1}"
  [[ -n "$2" ]] && url="${url}?${2}"
  curl -s -w "\n%{http_code}" "$url"
}

# json_post <path> <json-body>
# Authenticated POST; uses _AUTH_TOKEN.
json_post() {
  curl -s -w "\n%{http_code}" \
    -X POST "${BASE_URL}${1}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${_AUTH_TOKEN}" \
    -d "$2"
}

# json_put <path> <json-body>
# Authenticated PUT; uses _AUTH_TOKEN.
json_put() {
  curl -s -w "\n%{http_code}" \
    -X PUT "${BASE_URL}${1}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${_AUTH_TOKEN}" \
    -d "$2"
}

# json_delete <path>
# Authenticated DELETE; uses _AUTH_TOKEN.
json_delete() {
  curl -s -w "\n%{http_code}" \
    -X DELETE "${BASE_URL}${1}" \
    -H "Authorization: Bearer ${_AUTH_TOKEN}"
}

# acquire_token
# Logs in as the seed admin user and stores the JWT in _AUTH_TOKEN.
# Called once before the write-endpoint test sections run.
acquire_token() {
  _AUTH_TOKEN=$(curl -s -X POST "${BASE_URL}/api/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"admin123"}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))")
  if [[ -z "$_AUTH_TOKEN" ]]; then
    echo -e "${RED}ERROR: could not acquire auth token – is the server seeded?${RESET}" >&2
    exit 1
  fi
}

# cleanup_created
# Deletes any products created during the test run so the DB stays clean.
cleanup_created() {
  for id in "${_CREATED_IDS[@]}"; do
    json_delete "/api/products/${id}" > /dev/null
  done
}

# Python is used only for inline JSON arithmetic / key-checks; every modern
# Linux / macOS ships with python3.
py() { python3 -c "$1"; }

# record <name> <passed:0|1> [reason]
record() {
  local name="$1" ok="$2" reason="${3:-}"
  if [[ "$ok" -eq 0 ]]; then
    RESULTS+=("${GREEN}✅ PASS${RESET}  $name")
    (( PASS++ ))
  else
    RESULTS+=("${RED}❌ FAIL${RESET}  $name${reason:+$'\n'         ↳ $reason}")
    (( FAIL++ ))
  fi
}

# run_test <name> <function>
run_test() {
  local name="$1"; shift
  local output err_msg
  if output=$("$@" 2>&1); then
    record "$name" 0
  else
    record "$name" 1 "$output"
  fi
}

# ── individual test functions ───────────────────────────────────────────────

# ─ Search tests ─────────────────────────────────────────────────────────────

t_search_q_mouse() {
  local resp status body
  resp=$(json_get "/api/products/search" "q=mouse")
  status=$(tail -1 <<< "$resp")
  body=$(head -n -1 <<< "$resp")

  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import sys, json
products = json.loads('''$body''')
assert isinstance(products, list), 'body is not an array'
assert len(products) > 0, 'expected non-empty array for q=mouse'
for p in products:
    name = (p.get('name') or '').lower()
    desc = (p.get('description') or '').lower()
    assert 'mouse' in name or 'mouse' in desc, \
        f\"Product '{p.get('name')}' does not contain 'mouse' in name or description\"
" || return 1
}

t_search_category() {
  local resp status body
  resp=$(json_get "/api/products/search" "category=Electronics")
  status=$(tail -1 <<< "$resp")
  body=$(head -n -1 <<< "$resp")

  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import sys, json
products = json.loads('''$body''')
assert isinstance(products, list), 'body is not an array'
assert len(products) > 0, 'expected non-empty array for category=Electronics'
for p in products:
    assert p.get('category') == 'Electronics', \
        f\"Product '{p.get('name')}' has category '{p.get('category')}', expected 'Electronics'\"
" || return 1
}

t_search_min_price() {
  local resp status body
  resp=$(json_get "/api/products/search" "minPrice=50")
  status=$(tail -1 <<< "$resp")
  body=$(head -n -1 <<< "$resp")

  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import sys, json
products = json.loads('''$body''')
assert isinstance(products, list), 'body is not an array'
assert len(products) > 0, 'expected non-empty array for minPrice=50'
for p in products:
    assert (p.get('price') or 0) >= 50, \
        f\"Product '{p.get('name')}' has price {p.get('price')}, expected >= 50\"
" || return 1
}

t_search_max_price() {
  local resp status body
  resp=$(json_get "/api/products/search" "maxPrice=20")
  status=$(tail -1 <<< "$resp")
  body=$(head -n -1 <<< "$resp")

  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import sys, json
products = json.loads('''$body''')
assert isinstance(products, list), 'body is not an array'
assert len(products) > 0, 'expected non-empty array for maxPrice=20'
for p in products:
    assert (p.get('price') or 0) <= 20, \
        f\"Product '{p.get('name')}' has price {p.get('price')}, expected <= 20\"
" || return 1
}

t_search_combined() {
  local resp status body
  resp=$(json_get "/api/products/search" "q=USB&minPrice=10&maxPrice=50")
  status=$(tail -1 <<< "$resp")
  body=$(head -n -1 <<< "$resp")

  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import sys, json
products = json.loads('''$body''')
assert isinstance(products, list), 'body is not an array'
assert len(products) > 0, 'expected non-empty array for q=USB&minPrice=10&maxPrice=50'
for p in products:
    name = (p.get('name') or '').lower()
    desc = (p.get('description') or '').lower()
    assert 'usb' in name or 'usb' in desc, \
        f\"Product '{p.get('name')}' does not contain 'USB' in name or description\"
    price = p.get('price') or 0
    assert price >= 10, f\"Product '{p.get('name')}' has price {price}, expected >= 10\"
    assert price <= 50, f\"Product '{p.get('name')}' has price {price}, expected <= 50\"
" || return 1
}

t_search_no_results() {
  local resp status body
  resp=$(json_get "/api/products/search" "q=nonexistentxyz")
  status=$(tail -1 <<< "$resp")
  body=$(head -n -1 <<< "$resp")

  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import sys, json
products = json.loads('''$body''')
assert isinstance(products, list), 'body is not an array'
assert len(products) == 0, f'expected empty array, got {len(products)} products'
" || return 1
}

# ─ Stats tests ───────────────────────────────────────────────────────────────

t_stats_total_count() {
  local resp status body
  resp=$(json_get "/api/products/stats")
  status=$(tail -1 <<< "$resp")
  body=$(head -n -1 <<< "$resp")

  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import sys, json
s = json.loads('''$body''')
assert 'totalCount' in s, 'missing totalCount field'
assert isinstance(s['totalCount'], int), f'totalCount must be int, got {type(s[\"totalCount\"]).__name__}'
assert s['totalCount'] > 0, f'totalCount must be > 0, got {s[\"totalCount\"]}'
" || return 1
}

t_stats_average_price() {
  local resp status body
  resp=$(json_get "/api/products/stats")
  status=$(tail -1 <<< "$resp")
  body=$(head -n -1 <<< "$resp")

  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import sys, json
s = json.loads('''$body''')
assert 'averagePrice' in s, 'missing averagePrice field'
assert isinstance(s['averagePrice'], (int, float)), 'averagePrice must be a number'
assert s['averagePrice'] > 0, f'averagePrice must be > 0, got {s[\"averagePrice\"]}'
" || return 1
}

t_stats_min_max_price() {
  local resp status body
  resp=$(json_get "/api/products/stats")
  status=$(tail -1 <<< "$resp")
  body=$(head -n -1 <<< "$resp")

  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import sys, json
s = json.loads('''$body''')
assert 'minPrice' in s, 'missing minPrice field'
assert 'maxPrice' in s, 'missing maxPrice field'
assert s['minPrice'] is not None, 'minPrice must not be null'
assert s['maxPrice'] is not None, 'maxPrice must not be null'
assert isinstance(s['minPrice'], (int, float)), 'minPrice must be a number'
assert isinstance(s['maxPrice'], (int, float)), 'maxPrice must be a number'
assert s['maxPrice'] >= s['minPrice'], \
    f'maxPrice ({s[\"maxPrice\"]}) must be >= minPrice ({s[\"minPrice\"]})'
" || return 1
}

t_stats_category_count() {
  local resp status body
  resp=$(json_get "/api/products/stats")
  status=$(tail -1 <<< "$resp")
  body=$(head -n -1 <<< "$resp")

  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import sys, json
s = json.loads('''$body''')
assert 'categoryCount' in s, 'missing categoryCount field'
cc = s['categoryCount']
assert isinstance(cc, dict), f'categoryCount must be an object, got {type(cc).__name__}'
assert len(cc) > 0, 'categoryCount must have at least one category'
for cat, count in cc.items():
    assert isinstance(cat, str), f'category key must be string, got {type(cat).__name__}'
    assert isinstance(count, int) and count > 0, \
        f'count for {cat} must be a positive int, got {count}'
" || return 1
}

t_stats_category_sum() {
  local resp status body
  resp=$(json_get "/api/products/stats")
  status=$(tail -1 <<< "$resp")
  body=$(head -n -1 <<< "$resp")

  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import sys, json
s = json.loads('''$body''')
total = s['totalCount']
cat_sum = sum(s['categoryCount'].values())
assert cat_sum == total, \
    f'sum(categoryCount)={cat_sum} does not equal totalCount={total}'
" || return 1
}

# ─ Pagination / sorting tests ────────────────────────────────────────────────

t_paginate_structure() {
  local resp status body
  resp=$(json_get "/api/products" "page=1&limit=5")
  status=$(tail -1 <<< "$resp")
  body=$(head -n -1 <<< "$resp")

  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import sys, json
r = json.loads('''$body''')
for field in ('data', 'page', 'limit', 'total'):
    assert field in r, f'missing field: {field}'
assert isinstance(r['data'], list),  'data must be an array'
assert isinstance(r['page'],  int),  'page must be an integer'
assert isinstance(r['limit'], int),  'limit must be an integer'
assert isinstance(r['total'], int),  'total must be an integer'
assert r['page']  == 1, f'expected page=1, got {r[\"page\"]}'
assert r['limit'] == 5, f'expected limit=5, got {r[\"limit\"]}'
assert len(r['data']) == 5, f'expected 5 items in data, got {len(r[\"data\"])}'
" || return 1
}

t_paginate_no_overlap() {
  local resp1 resp2 body1 body2
  resp1=$(json_get "/api/products" "page=1&limit=5")
  body1=$(head -n -1 <<< "$resp1")
  resp2=$(json_get "/api/products" "page=2&limit=5")
  body2=$(head -n -1 <<< "$resp2")

  py "
import sys, json
p1 = json.loads('''$body1''')
p2 = json.loads('''$body2''')
ids1 = {p['id'] for p in p1['data']}
ids2 = {p['id'] for p in p2['data']}
overlap = ids1 & ids2
assert not overlap, f'pages 1 and 2 share product IDs: {overlap}'
assert len(ids1) > 0, 'page 1 returned no products'
assert len(ids2) > 0, 'page 2 returned no products'
" || return 1
}

t_sort_price_asc() {
  local resp status body
  resp=$(json_get "/api/products" "sort=price&order=asc&limit=100")
  status=$(tail -1 <<< "$resp")
  body=$(head -n -1 <<< "$resp")

  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import sys, json
r = json.loads('''$body''')
prices = [p['price'] for p in r['data'] if p.get('price') is not None]
assert prices == sorted(prices), \
    f'prices not in ascending order: {prices}'
" || return 1
}

t_sort_price_desc() {
  local resp status body
  resp=$(json_get "/api/products" "sort=price&order=desc&limit=100")
  status=$(tail -1 <<< "$resp")
  body=$(head -n -1 <<< "$resp")

  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import sys, json
r = json.loads('''$body''')
prices = [p['price'] for p in r['data'] if p.get('price') is not None]
assert prices == sorted(prices, reverse=True), \
    f'prices not in descending order: {prices}'
" || return 1
}

t_sort_name_asc() {
  local resp status body
  resp=$(json_get "/api/products" "sort=name&order=asc&limit=100")
  status=$(tail -1 <<< "$resp")
  body=$(head -n -1 <<< "$resp")

  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import sys, json
r = json.loads('''$body''')
names = [p['name'] for p in r['data'] if p.get('name') is not None]
assert names == sorted(names), \
    f'names not in lexicographic ascending order: {names}'
" || return 1
}

t_paginate_total_gt_data() {
  local resp status body
  resp=$(json_get "/api/products" "page=1&limit=5")
  status=$(tail -1 <<< "$resp")
  body=$(head -n -1 <<< "$resp")

  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import sys, json
r = json.loads('''$body''')
assert r['total'] > len(r['data']), \
    f'total ({r[\"total\"]}) should be greater than data length ({len(r[\"data\"])})'
" || return 1
}

t_paginate_out_of_bounds() {
  local resp status body
  resp=$(json_get "/api/products" "page=999&limit=10")
  status=$(tail -1 <<< "$resp")
  body=$(head -n -1 <<< "$resp")

  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import sys, json
r = json.loads('''$body''')
assert isinstance(r['data'], list), 'data must be an array'
assert len(r['data']) == 0, f'expected empty data array, got {len(r[\"data\"])} items'
" || return 1
}

# ─ Validation tests ──────────────────────────────────────────────────────────

# Helper: assert a response is 400 with an errors object containing the given key.
_assert_validation_error() {
  local status="$1" body="$2" field="$3"
  [[ "$status" -eq 400 ]] || { echo "Expected 400, got $status"; return 1; }
  py "
import sys, json
b = json.loads('''$body''')
assert 'errors' in b, f'missing top-level errors object: {b}'
assert isinstance(b['errors'], dict), f'errors must be an object, got {type(b[\"errors\"]).__name__}'
assert '${field}' in b['errors'], f'errors.${field} not present; got keys: {list(b[\"errors\"].keys())}'
assert isinstance(b['errors']['${field}'], str), f'errors.${field} must be a string'
" || return 1
}

t_validate_missing_name() {
  local resp status body
  resp=$(json_post "/api/products" '{"price":9.99,"category":"Electronics"}')
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  _assert_validation_error "$status" "$body" "name"
}

t_validate_negative_price() {
  local resp status body
  resp=$(json_post "/api/products" '{"name":"Test","price":-5,"category":"Electronics"}')
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  _assert_validation_error "$status" "$body" "price"
}

t_validate_zero_price() {
  local resp status body
  resp=$(json_post "/api/products" '{"name":"Test","price":0,"category":"Electronics"}')
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  _assert_validation_error "$status" "$body" "price"
}

t_validate_invalid_category() {
  local resp status body
  resp=$(json_post "/api/products" '{"name":"Test","price":9.99,"category":"InvalidCategory"}')
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  _assert_validation_error "$status" "$body" "category"
}

t_validate_update_negative_price() {
  local resp status body
  # Use any existing product – borrow first id from the catalogue
  local first_id
  first_id=$(curl -s "${BASE_URL}/api/products?limit=1" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'])")
  resp=$(json_put "/api/products/${first_id}" '{"price":-10}')
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  _assert_validation_error "$status" "$body" "price"
}

t_validate_errors_structure() {
  local resp status body
  # Send multiple bad fields at once – both name and price must appear in errors.
  resp=$(json_post "/api/products" '{"price":-1,"category":"InvalidCategory"}')
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 400 ]] || { echo "Expected 400, got $status"; return 1; }
  py "
import sys, json
b = json.loads('''$body''')
assert 'errors' in b, 'missing errors object'
for key, val in b['errors'].items():
    assert isinstance(key, str), f'error key must be str: {key}'
    assert isinstance(val, str), f'error value must be str for key {key}: {val}'
" || return 1
}

t_validate_valid_post() {
  local resp status body created_id
  resp=$(json_post "/api/products" '{"name":"__test_product__","price":1.99,"category":"Storage","stock":1}')
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 201 ]] || { echo "Expected 201, got $status; body: $body"; return 1; }
  py "
import sys, json
p = json.loads('''$body''')
assert 'id' in p and p['id'], 'created product must have an id'
assert p['name'] == '__test_product__', f'unexpected name: {p.get(\"name\")}'
" || return 1
  # Capture the id so we can clean up after the suite
  created_id=$(py "import json; print(json.loads('''$body''')['id'])")
  [[ -n "$created_id" ]] && _CREATED_IDS+=("$created_id")
}

t_validate_update_not_found() {
  local resp status body
  resp=$(json_put "/api/products/000000000000000000000000" '{"price":9.99}')
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 404 ]] || { echo "Expected 404, got $status; body: $body"; return 1; }
}

# ── run all tests ───────────────────────────────────────────────────────────

echo -e "\n${BOLD}SGarden API – Integration Tests${RESET}"
echo -e "Target: ${CYAN}${BASE_URL}${RESET}\n"

echo -e "${BOLD}── Search endpoint (/api/products/search) ─────────────────────────────${RESET}"
run_test "q=mouse → text match in name/description"         t_search_q_mouse
run_test "category=Electronics → exact category filter"     t_search_category
run_test "minPrice=50 → price >= 50"                        t_search_min_price
run_test "maxPrice=20 → price <= 20"                        t_search_max_price
run_test "q=USB&minPrice=10&maxPrice=50 → combined filters" t_search_combined
run_test "q=nonexistentxyz → empty array"                   t_search_no_results

echo ""
echo -e "${BOLD}── Stats endpoint (/api/products/stats) ───────────────────────────────${RESET}"
run_test "GET /stats → 200 with totalCount > 0"             t_stats_total_count
run_test "GET /stats → averagePrice is a positive number"   t_stats_average_price
run_test "GET /stats → minPrice and maxPrice, max >= min"   t_stats_min_max_price
run_test "GET /stats → categoryCount is an object"          t_stats_category_count
run_test "GET /stats → sum(categoryCount) == totalCount"    t_stats_category_sum

echo ""
echo -e "${BOLD}── Pagination & sorting (/api/products) ───────────────────────────────${RESET}"
run_test "page=1&limit=5 → data/page/limit/total fields present"  t_paginate_structure
run_test "page=1 and page=2 return non-overlapping IDs"           t_paginate_no_overlap
run_test "sort=price&order=asc → prices non-decreasing"           t_sort_price_asc
run_test "sort=price&order=desc → prices non-increasing"          t_sort_price_desc
run_test "sort=name&order=asc → names in lexicographic order"     t_sort_name_asc
run_test "page=1&limit=5 → total > len(data)"                     t_paginate_total_gt_data
run_test "page=999&limit=10 → 200 with empty data array"          t_paginate_out_of_bounds

echo ""
echo -e "${BOLD}── Validation (/api/products POST & PUT) ──────────────────────────────${RESET}"
acquire_token
run_test "POST missing name → 400 with errors.name"               t_validate_missing_name
run_test "POST price=-5 → 400 with errors.price"                  t_validate_negative_price
run_test "POST price=0 → 400 with errors.price"                   t_validate_zero_price
run_test "POST invalid category → 400 with errors.category"       t_validate_invalid_category
run_test "PUT price=-10 → 400 with errors.price"                  t_validate_update_negative_price
run_test "errors object has string values for all failing fields"  t_validate_errors_structure
run_test "POST valid payload → 201 with created product"          t_validate_valid_post
run_test "PUT /products/000000000000000000000000 → 404"           t_validate_update_not_found

cleanup_created

# ── summary ─────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}───────────────────────────────────────────────────────────────────────${RESET}"
for line in "${RESULTS[@]}"; do
  echo -e "  $line"
done
echo -e "${BOLD}───────────────────────────────────────────────────────────────────────${RESET}"

TOTAL=$(( PASS + FAIL ))
if [[ "$FAIL" -eq 0 ]]; then
  echo -e "\n  ${GREEN}${BOLD}${PASS}/${TOTAL} passed 🎉${RESET}\n"
  exit 0
else
  echo -e "\n  ${RED}${BOLD}${PASS}/${TOTAL} passed  (${FAIL} failed)${RESET}\n"
  exit 1
fi
