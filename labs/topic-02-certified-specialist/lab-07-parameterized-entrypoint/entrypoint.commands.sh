#!/bin/sh
# Task 4 — demonstrate subcommand dispatch (NOT an actual service manager).
set -eu
command="${1:-}"
case "$command" in
  start)
    printf 'Starting application with config: %s\n' "${2:-default}"
    ;;
  stop)
    printf '%s\n' 'Stopping application gracefully (simulation only)'
    ;;
  *)
    printf 'Usage: %s {start|stop} [config]\n' "$0" >&2
    exit 64
    ;;
esac
