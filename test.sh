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

# ── colours ────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── helpers ────────────────────────────────────────────────────────────────

# json_get <path> [query-string]
# Performs a GET request and prints "<status_code> <body>" to stdout.
json_get() {
  local url="${BASE_URL}${1}"
  [[ -n "$2" ]] && url="${url}?${2}"
  curl -s -w "\n%{http_code}" "$url"
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
