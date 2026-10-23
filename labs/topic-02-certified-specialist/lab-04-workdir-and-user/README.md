# Lab 04 — Setting `WORKDIR` and `USER` Instructions

**Domain 5 → Linux and Open Source → Red Hat 1 → Topic 2: Red Hat Certified Specialist in Containers**  
**Lab date:** 23 October 2026  
**Maintainer:** Hafiz Mohammad Sunasara  
**Status:** Completed (learner-reported; LMS completion indicator retained)  
**Environment:** Al Nafi Ubuntu lab, Podman, Red Hat UBI 9 Minimal

> **Goal:** Configure a consistent working directory, create a dedicated non-root application user, and understand how Linux file permissions affect a container.

## Lab files — start here

| File | Role |
| --- | --- |
| [`Containerfile.workdir`](Containerfile.workdir) | **Task 1:** root-user baseline with `WORKDIR /app` |
| [`Containerfile`](Containerfile) | **Task 2 onward:** non-root user example |
| [`DEEP-DIVE.md`](DEEP-DIVE.md) | Step-by-step concepts, security reasoning, failure cases, interview questions |
| [`evidence/01-course-platform-completion.png`](evidence/01-course-platform-completion.png) | Course interface completion indicator (**not** terminal output) |

These Containerfiles are **reconstructed examples based on the lab instructions**, not original file exports from the temporary training environment.

## What you'll learn

1. Why `WORKDIR` makes build-time and runtime paths predictable.
2. How `useradd` creates an identity in an image, and why `chown` matters.
3. How `USER` changes the default user for subsequent build steps and container processes.
4. How to test read/write restrictions without disabling host security.
5. Why non-root inside a container and rootless Podman on the host are different concepts.

## Prerequisites

- Podman installed (`podman --version`). The instructor's example version need not match yours exactly.
- A Linux shell and registry access to pull `registry.access.redhat.com/ubi9/ubi-minimal`.
- Sufficient rights to run rootless containers.

This exercise follows the course's unpinned UBI9 Minimal reference. For long-lived deployments, choose a maintained version or verified digest instead of relying indefinitely on a moving tag.

---

## Task 1 — Set and verify `WORKDIR`

### 1. Create your working directory

```bash
mkdir -p ~/container-security-lab
cd ~/container-security-lab
podman --version
```

### 2. Build the baseline image

Copy the adjacent [`Containerfile.workdir`](Containerfile.workdir) into this directory. It contains:

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal
LABEL maintainer="Hafiz Mohammad Sunasara"
WORKDIR /app
RUN pwd > /tmp/workdir.log && whoami >> /tmp/workdir.log
```

Then run:

```bash
podman build -f Containerfile.workdir -t workdir-demo .
```

**Why these lines work:** `WORKDIR /app` selects (and creates if needed) the directory for later build steps. `RUN` executes during image construction and writes the directory and effective username to `/tmp/workdir.log`.

### 3. Verify build and runtime

```bash
podman run --rm workdir-demo cat /tmp/workdir.log
podman run --rm workdir-demo pwd
```

**Expected (not captured as terminal evidence in the supplied screenshot):**

```text
/app
root
```

The second command should print `/app`. `WORKDIR` changes the image/container working directory, **not** your host terminal's current directory.

---

## Task 2 — Create and use a non-root user

### 1. Build the complete security image

Use the adjacent [`Containerfile`](Containerfile):

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal
LABEL maintainer="Hafiz Mohammad Sunasara"
WORKDIR /app
RUN pwd > /tmp/workdir.log && whoami >> /tmp/workdir.log
RUN microdnf install -y shadow-utils && \
    microdnf clean all && \
    useradd -u 1001 -d /home/appuser -m appuser && \
    chown -R appuser:appuser /app
USER appuser
RUN whoami > /tmp/user.log && ls -ld /app >> /tmp/user.log
```

Build it:

```bash
podman build -f Containerfile -t nonroot-demo .
```

**Line-by-line meaning:**

- `microdnf install ... shadow-utils`: installs tools that provide `useradd`.
- `useradd -u 1001 -d /home/appuser -m appuser`: creates a named account, UID 1001, and its home.
- `chown -R appuser:appuser /app`: makes `/app` owned by that account so it can write there.
- `USER appuser`: changes the image's default process identity.
- Final `RUN`: records identity and `/app` ownership during the build.

### 2. Verify user and filesystem

```bash
podman run --rm nonroot-demo cat /tmp/user.log
podman run --rm nonroot-demo whoami
podman run --rm nonroot-demo id
podman image inspect nonroot-demo --format '{{.Config.User}}'
```

**Expected format (illustrative; timestamps and exact mode text may differ):**

```text
appuser
drwxr-xr-x ... appuser appuser ... /app
```

`whoami` should display `appuser`, `id` should show UID 1001, and image inspection should show `appuser` as its configured default user.

### 3. Test a writable path

```bash
podman run --rm nonroot-demo touch /app/testfile
```

Expected: exit code 0 and no error, because the user owns `/app`.

---

## Task 3 — Validate permissions and process identity

### 1. Try a restricted write

```bash
podman run --rm nonroot-demo touch /root/blocked-file
```

**Expected:** an error such as `Permission denied`. That restriction is the **desired observation**, not a failed lab.

The original lesson also asks you to test:

```bash
podman run --rm nonroot-demo touch /sys/kernel/profiling
```

This can fail because `/sys` is read-only or restricted even for root in a container. It is **not sufficient by itself** to demonstrate that `USER appuser` works. Use `id` and the `/root` test alongside it.

### 2. Inspect a running process

```bash
podman run -d --name testuser nonroot-demo sleep 300
podman top testuser
podman exec testuser id
podman rm -f testuser
```

`podman top` is used because UBI Minimal may not contain `ps`. The `podman exec ... id` output should identify `appuser`/UID 1001. Remove only the named test container after inspection.

---

## Task 4 — Compare root and non-root behavior

```bash
podman run --rm --user root workdir-demo whoami
podman run --rm nonroot-demo whoami
```

**Expected contrast:**

```text
root
appuser
```

Note: running as root **inside a container** does not automatically grant unrestricted access to the host. Container isolation, capabilities, user namespaces, mount modes and other controls still apply. The `USER` directive is one part of defense in depth.

### Optional: one-line security checks

```bash
podman inspect nonroot-demo --format '{{.Config.User}}'  # image inspection is preferable below
podman image inspect nonroot-demo --format '{{.Config.User}}'
podman run --rm nonroot-demo sh -c 'pwd; whoami; id; ls -ld /app'
```

---

## Results and evidence

| Item | Evidence status |
| --- | --- |
| Lab 04 marked completed on Al Nafi course interface | **Visible in retained screenshot** |
| `WORKDIR` / `USER` commands and expected terminal output | **Reproducible instructions; terminal outputs not retained here** |
| Permission test and running-process checks | **Documented test plan; not independently shown in the screenshot** |

![Lab 04 course completion indicator](evidence/01-course-platform-completion.png)

**Evidence boundary:** The screenshot displays the course page's completion indicator. It does **not** show terminal command histories or verify each individual operation. No test output has been fabricated.

## Troubleshooting table

| Issue | Check | Resolution |
| --- | --- | --- |
| Image pull fails | Network, exact registry/image reference, access | Retry `podman pull registry.access.redhat.com/ubi9/ubi-minimal` |
| `useradd: command not found` | Did `microdnf install -y shadow-utils` succeed? | Check package installation output and rebuild |
| `/app` write denied | `ls -ld /app`, `id`, Containerfile order | Run `chown` **before** `USER` |
| `whoami`/`ps` unavailable | Minimal image packages | Prefer `id`, `podman top`, or install only necessary tools |
| `/sys` test denied | Read-only kernel filesystem/mount | Treat as expected restriction; do not confuse it with proof of non-root UID |
| Build permission error | Rootless Podman storage, user namespace, image filesystem | Inspect the exact error; do **not** default to `--privileged` or disable SELinux |

## Security lessons

- Give processes the minimum privileges they need (**least privilege**).
- Never assume `USER appuser` automatically fixes all filesystem permissions.
- Put ownership changes before switching users.
- Treat rootless Podman (host-side) and non-root `USER` (container-side) as separate controls.
- Validate the **result**, not merely whether the image build completed.

For the deeper explanation, read **[DEEP-DIVE.md](DEEP-DIVE.md)**.

## Next lab and cleanup

**Next:** Topic 2 — Lab 05: Securing Images with Least Privilege.

Optional cleanup **only if you no longer need these two images**:

```bash
podman rm -f testuser 2>/dev/null || true
podman rmi workdir-demo nonroot-demo
```

Avoid broad `podman image prune -a` or `rm -rf` commands that may affect unrelated files or work.

---

**Related:** [Lab 03 — ADD vs COPY](../lab-03-add-vs-copy/README.md) · [Topic 2 folder](../) · [Lab index](../../LABS-INDEX.md)
