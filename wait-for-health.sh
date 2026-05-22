#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# wait-for-health.sh
#
# Polls GET <url>/api/health until it returns HTTP 200 or the timeout expires.
#
# Usage:
#   ./wait-for-health.sh <base-url> [max-seconds]
#
# Arguments:
#   base-url     Base URL of the server, e.g. http://localhost:4000
#   max-seconds  How long to wait before giving up (default: 30)
#
# Exit codes:
#   0 – server responded with 200 within the time limit
#   1 – timed out
# ---------------------------------------------------------------------------

set -euo pipefail

BASE_URL="${1:?Usage: $0 <base-url> [max-seconds]}"
MAX_WAIT="${2:-30}"
HEALTH_URL="${BASE_URL}/api/health"

echo "Waiting for ${HEALTH_URL} (timeout: ${MAX_WAIT}s)..."

for i in $(seq 1 "$MAX_WAIT"); do
  if curl -sf "$HEALTH_URL" > /dev/null 2>&1; then
    echo "Server ready after ${i}s"
    exit 0
  fi
  sleep 1
done

echo "ERROR: server did not become healthy within ${MAX_WAIT}s" >&2
exit 1

