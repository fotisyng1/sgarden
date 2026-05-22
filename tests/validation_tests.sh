#!/usr/bin/env bash
# tests/validation_tests.sh – product create/update validation tests.
# Sourced by test.sh; relies on helpers.sh and an acquired _AUTH_TOKEN.

# Assert a response is 400 with errors.<field>.
_assert_field_error() {
  local status="$1" body="$2" field="$3"
  [[ "$status" -eq 400 ]] || { echo "Expected 400, got $status"; return 1; }
  py "
import json
b = json.loads('''$body''')
assert 'errors' in b, f'missing errors object in: {b}'
assert '${field}' in b['errors'], \
    f'errors.${field} not present; got: {list(b[\"errors\"].keys())}'
assert isinstance(b['errors']['${field}'], str)
"
}

t_validate_missing_name() {
  local resp status body
  resp=$(json_post "/api/products" '{"price":9.99,"category":"Electronics"}')
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  _assert_field_error "$status" "$body" "name"
}

t_validate_negative_price() {
  local resp status body
  resp=$(json_post "/api/products" '{"name":"Test","price":-5,"category":"Electronics"}')
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  _assert_field_error "$status" "$body" "price"
}

t_validate_zero_price() {
  local resp status body
  resp=$(json_post "/api/products" '{"name":"Test","price":0,"category":"Electronics"}')
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  _assert_field_error "$status" "$body" "price"
}

t_validate_invalid_category() {
  local resp status body
  resp=$(json_post "/api/products" '{"name":"Test","price":9.99,"category":"InvalidCategory"}')
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  _assert_field_error "$status" "$body" "category"
}

t_validate_update_negative_price() {
  local first_id resp status body
  first_id=$(curl -s "${BASE_URL}/api/products?limit=1" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['id'])")
  resp=$(json_put "/api/products/${first_id}" '{"price":-10}')
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  _assert_field_error "$status" "$body" "price"
}

t_validate_errors_structure() {
  local resp status body
  resp=$(json_post "/api/products" '{"price":-1,"category":"InvalidCategory"}')
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 400 ]] || { echo "Expected 400, got $status"; return 1; }
  py "
import json
b = json.loads('''$body''')
assert 'errors' in b, 'missing errors object'
for k, v in b['errors'].items():
    assert isinstance(k, str) and isinstance(v, str), \
        f'error entry must be str:str, got {k!r}:{v!r}'
"
}

t_validate_valid_post() {
  local resp status body created_id
  resp=$(json_post "/api/products" '{"name":"__test_product__","price":1.99,"category":"Storage","stock":1}')
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 201 ]] || { echo "Expected 201, got $status; body: $body"; return 1; }
  py "
import json
p = json.loads('''$body''')
assert 'id' in p and p['id'], 'created product must have an id'
assert p.get('name') == '__test_product__'
"
  created_id=$(py "import json; print(json.loads('''$body''')['id'])")
  [[ -n "$created_id" ]] && _CREATED_PRODUCT_IDS+=("$created_id")
}

t_validate_update_not_found() {
  local resp status body
  resp=$(json_put "/api/products/000000000000000000000000" '{"price":9.99}')
  status=$(tail -1 <<< "$resp"); body=$(head -n -1 <<< "$resp")
  [[ "$status" -eq 404 ]] || { echo "Expected 404, got $status"; return 1; }
}

run_validation_tests() {
  echo -e "${BOLD}── Validation  POST & PUT /api/products ──────────────────────────────${RESET}"
  run_test "POST missing name → 400 errors.name"               t_validate_missing_name
  run_test "POST price=-5 → 400 errors.price"                  t_validate_negative_price
  run_test "POST price=0 → 400 errors.price"                   t_validate_zero_price
  run_test "POST invalid category → 400 errors.category"       t_validate_invalid_category
  run_test "PUT price=-10 → 400 errors.price"                  t_validate_update_negative_price
  run_test "errors object has string values for all fields"     t_validate_errors_structure
  run_test "POST valid payload → 201 with created product"      t_validate_valid_post
  run_test "PUT /000000000000000000000000 → 404"               t_validate_update_not_found
}

