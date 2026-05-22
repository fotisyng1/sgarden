#!/usr/bin/env bash
# tests/stats_tests.sh – GET /api/products/stats test suite.
# Sourced by test.sh; relies on helpers.sh being sourced first.

t_stats_total_count() {
  local resp status body
  resp=$(json_get "/api/products/stats")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
s = json.loads('''$body''')
assert 'totalCount' in s, 'missing totalCount'
assert isinstance(s['totalCount'], int) and s['totalCount'] > 0
"
}

t_stats_average_price() {
  local resp status body
  resp=$(json_get "/api/products/stats")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
s = json.loads('''$body''')
assert 'averagePrice' in s, 'missing averagePrice'
assert isinstance(s['averagePrice'], (int, float)) and s['averagePrice'] > 0
"
}

t_stats_min_max_price() {
  local resp status body
  resp=$(json_get "/api/products/stats")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
s = json.loads('''$body''')
assert s.get('minPrice') is not None and s.get('maxPrice') is not None
assert isinstance(s['minPrice'], (int, float))
assert isinstance(s['maxPrice'], (int, float))
assert s['maxPrice'] >= s['minPrice'], \
    f'maxPrice {s[\"maxPrice\"]} < minPrice {s[\"minPrice\"]}'
"
}

t_stats_category_count() {
  local resp status body
  resp=$(json_get "/api/products/stats")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
s = json.loads('''$body''')
cc = s.get('categoryCount', {})
assert isinstance(cc, dict) and len(cc) > 0, 'categoryCount must be a non-empty object'
for k, v in cc.items():
    assert isinstance(k, str) and isinstance(v, int) and v > 0
"
}

t_stats_category_sum() {
  local resp status body
  resp=$(json_get "/api/products/stats")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
s = json.loads('''$body''')
cat_sum = sum(s['categoryCount'].values())
assert cat_sum == s['totalCount'], \
    f'sum(categoryCount)={cat_sum} != totalCount={s[\"totalCount\"]}'
"
}

run_stats_tests() {
  echo -e "${BOLD}── Stats   GET /api/products/stats ───────────────────────────────────${RESET}"
  run_test "totalCount > 0"                           t_stats_total_count
  run_test "averagePrice is a positive number"        t_stats_average_price
  run_test "minPrice and maxPrice, max >= min"        t_stats_min_max_price
  run_test "categoryCount is a non-empty object"      t_stats_category_count
  run_test "sum(categoryCount) == totalCount"         t_stats_category_sum
}

