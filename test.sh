#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test.sh – SGarden API integration-test orchestrator.
#
# Usage:  ./test.sh [BASE_URL]
# Default BASE_URL: http://localhost:4000
#
# Each concern lives in its own file under tests/:
#   helpers.sh          – shared HTTP helpers, runner, auth, cleanup
#   search_tests.sh     – GET /api/products/search
#   stats_tests.sh      – GET /api/products/stats
#   pagination_tests.sh – GET /api/products (pagination & sorting)
#   validation_tests.sh – POST/PUT /api/products (input validation)
#   orders_tests.sh     – full CRUD for /api/orders
# ---------------------------------------------------------------------------

set -uo pipefail

BASE_URL="${1:-http://localhost:4000}"

# ── Shared state (written by helpers, read by every test file) ───────────────
PASS=0
FAIL=0
RESULTS=()
_AUTH_TOKEN=""
_CREATED_PRODUCT_IDS=()
_CREATED_ORDER_IDS=()

# ── Source helpers then each test suite ──────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=tests/helpers.sh
source "${SCRIPT_DIR}/tests/helpers.sh"
source "${SCRIPT_DIR}/tests/search_tests.sh"
source "${SCRIPT_DIR}/tests/stats_tests.sh"
source "${SCRIPT_DIR}/tests/pagination_tests.sh"
source "${SCRIPT_DIR}/tests/validation_tests.sh"
source "${SCRIPT_DIR}/tests/orders_tests.sh"
source "${SCRIPT_DIR}/tests/stock_tests.sh"

# ── Run suites ───────────────────────────────────────────────────────────────
echo -e "\n${BOLD}SGarden API – Integration Tests${RESET}"
echo -e "Target: ${CYAN}${BASE_URL}${RESET}\n"

run_search_tests
echo ""
run_stats_tests
echo ""
run_pagination_tests

# Write-endpoint suites require authentication.
echo ""
acquire_token
run_validation_tests
echo ""
run_orders_tests
echo ""
run_stock_tests

# Clean up any resources created during the run.
cleanup_created

# ── Summary ──────────────────────────────────────────────────────────────────
TOTAL=$(( PASS + FAIL ))
echo ""
echo -e "${BOLD}───────────────────────────────────────────────────────────────────────${RESET}"
for line in "${RESULTS[@]}"; do
  echo -e "  $line"
done
echo -e "${BOLD}───────────────────────────────────────────────────────────────────────${RESET}"

if [[ "$FAIL" -eq 0 ]]; then
  echo -e "\n  ${GREEN}${BOLD}${PASS}/${TOTAL} passed 🎉${RESET}\n"
  exit 0
else
  echo -e "\n  ${RED}${BOLD}${PASS}/${TOTAL} passed  (${FAIL} failed)${RESET}\n"
  exit 1
fi
