#!/usr/bin/env bash
# End-to-end check on one machine: JARVIS (demo model, console SMS) + mock AzamPay
# + the Flutter app's real HTTP client. Optionally drives the web build in Chromium.
#
#   jarvis/devtools/e2e.sh            # API journey only
#   E2E_UI=1 jarvis/devtools/e2e.sh   # also run the browser test (needs build/web)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="${E2E_WORK:-$(mktemp -d)}"
PY="${PYTHON:-python3}"
SECRET="e2e-callback-secret"
API_PORT=8765 MOCK_PORT=8766 WEB_PORT=8080
pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT

wait_for() { for _ in $(seq 1 50); do curl -s --noproxy '*' -o /dev/null "$1" && return 0; sleep 0.2; done; echo "timeout: $1"; exit 1; }

"$PY" "$ROOT/jarvis/devtools/mock_azampay.py" --port $MOCK_PORT \
  --callback "http://127.0.0.1:$API_PORT/v1/pay/azampay/callback?key=$SECRET" > "$WORK/mock.log" 2>&1 &
pids+=($!)

(
  cd "$ROOT/jarvis"
  JARVIS_ENV=dev JARVIS_LLM=demo JARVIS_SMS_PROVIDER=console \
  JARVIS_DB="$WORK/e2e.db" JARVIS_CONTENT_DIR="$WORK/content" JARVIS_ADMIN_KEY=e2e-admin \
  JARVIS_CORS_ORIGINS="http://127.0.0.1:$WEB_PORT" \
  JARVIS_LEGACY_VIDEOS_URL="http://127.0.0.1:$MOCK_PORT/api/week_videos?week={week}" \
  AZAMPAY_APP_NAME=masomo AZAMPAY_CLIENT_ID=id AZAMPAY_CLIENT_SECRET=secret AZAMPAY_API_KEY=key \
  AZAMPAY_AUTH_URL="http://127.0.0.1:$MOCK_PORT" AZAMPAY_CHECKOUT_URL="http://127.0.0.1:$MOCK_PORT" \
  AZAMPAY_CALLBACK_SECRET=$SECRET \
  exec "$PY" -m uvicorn jarvis.server:app --host 127.0.0.1 --port $API_PORT
) > "$WORK/api.log" 2>&1 &
pids+=($!)

wait_for "http://127.0.0.1:$MOCK_PORT/checkouts"
wait_for "http://127.0.0.1:$API_PORT/health"

echo "== API journey (Flutter HTTP client -> JARVIS -> mock AzamPay)"
(cd "$ROOT" && NO_PROXY='*' LIVE_API="http://127.0.0.1:$API_PORT" flutter test test_live)

echo "== Admin report"
curl -s --noproxy '*' -H "X-Admin-Key: e2e-admin" "http://127.0.0.1:$API_PORT/v1/admin/report" ; echo

if [[ "${E2E_UI:-0}" == "1" ]]; then
  echo "== Browser test (web build in Chromium)"
  (cd "$ROOT/build/web" && exec "$PY" -m http.server $WEB_PORT --bind 127.0.0.1) > "$WORK/web.log" 2>&1 &
  pids+=($!)
  wait_for "http://127.0.0.1:$WEB_PORT/"
  NODE_PATH="$(npm root -g)" E2E_OUT="${E2E_OUT:-$WORK/shots}" WEB_URL="http://127.0.0.1:$WEB_PORT" \
    API_URL="http://127.0.0.1:$API_PORT" node "$ROOT/jarvis/devtools/ui_e2e.js"
fi
echo "== All end-to-end checks passed (logs in $WORK)"
