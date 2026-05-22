#!/usr/bin/env bash
# tests/pagination_tests.sh – GET /api/products pagination & sorting tests.
# Sourced by test.sh; relies on helpers.sh being sourced first.

t_paginate_structure() {
  local resp status body
  resp=$(json_get "/api/products" "page=1&limit=5")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
r = json.loads('''$body''')
for f in ('data','page','limit','total'):
    assert f in r, f'missing field: {f}'
assert isinstance(r['data'], list)
assert r['page'] == 1 and r['limit'] == 5
assert len(r['data']) == 5
"
}

t_paginate_no_overlap() {
  local body1 body2
  body1=$(head -n -1 <<< "$(json_get "/api/products" "page=1&limit=5")")
  body2=$(head -n -1 <<< "$(json_get "/api/products" "page=2&limit=5")")
  py "
import json
p1 = json.loads('''$body1'''); p2 = json.loads('''$body2''')
ids1 = {p['id'] for p in p1['data']}; ids2 = {p['id'] for p in p2['data']}
overlap = ids1 & ids2
assert not overlap, f'pages share IDs: {overlap}'
assert ids1 and ids2
"
}

t_sort_price_asc() {
  local resp status body
  resp=$(json_get "/api/products" "sort=price&order=asc&limit=100")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
prices = [p['price'] for p in json.loads('''$body''')['data'] if p.get('price') is not None]
assert prices == sorted(prices), f'not ascending: {prices}'
"
}

t_sort_price_desc() {
  local resp status body
  resp=$(json_get "/api/products" "sort=price&order=desc&limit=100")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
prices = [p['price'] for p in json.loads('''$body''')['data'] if p.get('price') is not None]
assert prices == sorted(prices, reverse=True), f'not descending: {prices}'
"
}

t_sort_name_asc() {
  local resp status body
  resp=$(json_get "/api/products" "sort=name&order=asc&limit=100")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
names = [p['name'] for p in json.loads('''$body''')['data'] if p.get('name')]
assert names == sorted(names), f'not lexicographic: {names}'
"
}

t_paginate_total_gt_data() {
  local resp status body
  resp=$(json_get "/api/products" "page=1&limit=5")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
r = json.loads('''$body''')
assert r['total'] > len(r['data']), \
    f'total ({r[\"total\"]}) not > data length ({len(r[\"data\"])})'
"
}

t_paginate_out_of_bounds() {
  local resp status body
  resp=$(json_get "/api/products" "page=999&limit=10")
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 200 ]] || { echo "Expected 200, got $status"; return 1; }
  py "
import json
r = json.loads('''$body''')
assert len(r['data']) == 0, f'expected empty data, got {len(r[\"data\"])} items'
"
}

run_pagination_tests() {
  echo -e "${BOLD}── Pagination & Sorting  GET /api/products ───────────────────────────${RESET}"
  run_test "page=1&limit=5 → data/page/limit/total fields present"  t_paginate_structure
  run_test "page=1 and page=2 return non-overlapping IDs"           t_paginate_no_overlap
  run_test "sort=price&order=asc → prices non-decreasing"           t_sort_price_asc
  run_test "sort=price&order=desc → prices non-increasing"          t_sort_price_desc
  run_test "sort=name&order=asc → names in lexicographic order"     t_sort_name_asc
  run_test "page=1&limit=5 → total > len(data)"                     t_paginate_total_gt_data
  run_test "page=999&limit=10 → 200 with empty data array"          t_paginate_out_of_bounds
}

