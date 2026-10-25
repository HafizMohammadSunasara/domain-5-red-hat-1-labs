#!/bin/sh
# Run on the *container host* after starting exposed-app, e.g.
#   sh tests/smoke-test.sh 9090
# Read-only test: does not create, stop, or remove any containers.
set -eu
PORT="${1:-8080}"
case "$PORT" in
    ''|*[!0-9]*) echo "ERROR: port must be numeric" >&2; exit 2 ;;
esac
URL="http://127.0.0.1:$PORT/"
printf 'Checking %s\n' "$URL"
BODY="$(curl --fail --silent --show-error --max-time 8 "$URL")"
EXPECTED='Hello from the exposed container port!'
if [ "$BODY" = "$EXPECTED" ]; then
    echo "PASS: HTTP response matches expected lab text"
else
    printf 'FAIL: unexpected response: %s\n' "$BODY" >&2
    exit 1
fi
