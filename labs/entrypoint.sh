#!/bin/sh
# Startup wrapper: display the command and replace this shell with it.
echo "Starting container with arguments: $@"
exec "$@"
