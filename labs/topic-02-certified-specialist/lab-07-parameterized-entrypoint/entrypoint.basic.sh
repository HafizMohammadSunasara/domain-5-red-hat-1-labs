#!/bin/sh
# Task 1 — initialize a container and inspect its execution context.
set -eu
printf '%s\n' 'Container starting...'
printf 'Executing as user: %s\n' "$(whoami)"
printf 'Current directory: %s\n' "$(pwd)"
