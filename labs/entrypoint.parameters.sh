#!/bin/sh
# Task 2 — inspect positional arguments, then invoke the supplied command.
set -eu
printf 'Container starting with arguments: %s\n' "$*"
printf 'First argument: %s\n' "${1:-none}"
printf 'Second argument: %s\n' "${2:-none}"
if [ "$#" -eq 0 ]; then
  printf '%s\n' 'No command supplied; nothing to execute.' >&2
  exit 64
fi
exec "$@"
