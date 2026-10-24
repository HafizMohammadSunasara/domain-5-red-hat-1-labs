#!/bin/sh
# Task 3 — configuration via an explicitly defined environment variable.
set -eu
case "${ENV_MODE:-}" in
  development)
    printf '%s\n' 'DEVELOPMENT MODE: Debug features enabled (demo message only)'
    ;;
  production)
    printf '%s\n' 'PRODUCTION MODE: Strict settings applied (demo message only)'
    ;;
  '')
    printf '%s\n' 'No ENV_MODE specified, running in default mode'
    ;;
  *)
    printf 'Unsupported ENV_MODE: %s\n' "$ENV_MODE" >&2
    exit 64
    ;;
esac
if [ "$#" -eq 0 ]; then
  printf '%s\n' 'No runtime command provided.' >&2
  exit 64
fi
exec "$@"
