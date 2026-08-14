#!/usr/bin/env bash
set -euo pipefail

PORT_FILE="${X300_DEBUG_UI_PORT_FILE:-/tmp/x300-debug-ui.json}"
COMMAND="${1:-health}"
shift || true

if [[ ! -f "$PORT_FILE" ]]; then
    echo "debug ui port file missing: $PORT_FILE" >&2
    exit 1
fi

PORT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["port"])' "$PORT_FILE")"
URL="http://127.0.0.1:${PORT}/${COMMAND}"

QUERY=""
if [[ $# -gt 0 ]]; then
    QUERY="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.urlencode([a.split("=", 1) for a in sys.argv[1:]]))' "$@")"
fi

if [[ -n "$QUERY" ]]; then
    URL="${URL}?${QUERY}"
fi

curl -sS "$URL"
echo
