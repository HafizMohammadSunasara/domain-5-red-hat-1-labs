#!/usr/bin/env bash
# Reproduce and validate Lab 04; execute on a machine with Podman installed.
# Does not remove previously created images or modify other projects.
set -euo pipefail
cd "$(dirname "$0")"

info() { printf '\n==> %s\n' "$*"; }
info "Podman version"
podman --version

info "Build the WORKDIR-only image"
podman build -f Containerfile.workdir -t workdir-demo .
info "Task 1: WORKDIR baseline must be /app and root"
actual=$(podman run --rm workdir-demo cat /tmp/workdir.log)
printf '%s\n' "$actual"
[ "$actual" = $'/app\nroot' ] || { echo 'FAIL: unexpected build-time workdir log'; exit 1; }
runtime_dir=$(podman run --rm workdir-demo pwd)
[ "$runtime_dir" = '/app' ] || { echo "FAIL: runtime WORKDIR was $runtime_dir"; exit 1; }

info "Build the non-root image"
podman build -f Containerfile -t nonroot-demo .
info "Task 2: user identity and directory owner"
podman run --rm nonroot-demo cat /tmp/user.log
uid=$(podman run --rm nonroot-demo id -u)
name=$(podman run --rm nonroot-demo whoami)
[ "$uid" = '1001' ] || { echo "FAIL: UID is $uid, expected 1001"; exit 1; }
[ "$name" = 'appuser' ] || { echo "FAIL: user is $name"; exit 1; }
podman run --rm nonroot-demo touch /app/testfile

info "Task 3: expect a permissions failure writing under /root"
if podman run --rm nonroot-demo touch /root/blocked-file; then
    echo 'FAIL: non-root container unexpectedly wrote to /root'
    exit 1
else
    echo 'PASS: non-root container cannot write into /root (expected denial)'
fi

info "Task 4: verify root override vs non-root default"
rootname=$(podman run --rm --user root workdir-demo whoami)
[ "$rootname" = 'root' ] || { echo 'FAIL: root comparison'; exit 1; }
[ "$(podman run --rm nonroot-demo whoami)" = 'appuser' ] || { echo 'FAIL: appuser runtime'; exit 1; }
podman image inspect nonroot-demo --format '{{.Config.User}}'

info "All automated checks passed. Optional process check:"
echo '  podman run -d --name lab04-testuser nonroot-demo sleep 300'
echo '  podman top lab04-testuser'
echo '  podman exec lab04-testuser id'
echo '  podman rm -f lab04-testuser'
