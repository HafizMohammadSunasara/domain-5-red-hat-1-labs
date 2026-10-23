# Deep Dive — `WORKDIR`, `USER`, Linux Identity and Container Hardening

**A durable learning reference:** basic mental models → commands → filesystem internals → threat model → OpenShift constraints → production patterns → troubleshooting exercises.

> This is instructional material, not a record of enterprise deployment or a claim that every test listed here was personally executed. See [the lab README](README.md) for user-reported completion and evidence boundaries.

## Reading map

1. How a container starts; images vs runtime processes
2. The problem `WORKDIR` solves
3. How Linux filesystem permissions really work
4. `USER`: identity versus ownership
5. Anatomy of the two Containerfiles
6. Root, rootless Podman and user namespaces
7. Why default non-root helps security (and its limits)
8. Negative testing and reliable evidence
9. OpenShift's arbitrary-UID model
10. Better application-image designs
11. Common mistakes and incident playbooks
12. Interview questions, experiments and a learning checklist

---

## 1. Start at zero: what happens when a container runs?

An **image** consists of a filesystem plus metadata. The filesystem contains binaries, libraries, users/groups database files and your application. Metadata includes entries for the default user, working directory, environment, command/entrypoint and more.

`podman build` reads a Containerfile top-to-bottom. Some lines change **metadata** (`WORKDIR`, `USER`, `LABEL`); others execute commands and add filesystem changes (`RUN`). When `podman run` creates a container, Podman sets up namespaces/mounts/cgroups and starts a process from the image's configured environment and command (or your explicit override).

Two questions every engineer should ask before deployment:

- **Where will the process start?** The current working directory affects relative paths, file creation, module loading and command behavior.
- **Who will the process be?** The effective UID and groups affect file reads/writes and access checks.

A successful image build proves only that the build finished. It does **not** prove the runtime application can read its config, bind the desired port, write its state, or recover after a failure.

## 2. `WORKDIR`: not just `cd`

### 2.1 What `WORKDIR /app` actually changes

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal
WORKDIR /app
RUN pwd
```

When the builder reaches `WORKDIR /app`, it sets the current directory for later `RUN` commands and sets image metadata that runtime processes use as the default directory. If `/app` does not exist, it is created.

Compare with this weaker design:

```dockerfile
RUN cd /app && some-command
RUN pwd
```

The `cd` inside the first `RUN` changes the directory of **that shell invocation only**. A later `RUN` starts a new instruction and does not inherit a transient shell `cd`. `WORKDIR` does persist in the image configuration for subsequent steps.

### 2.2 Relative paths and composition

```dockerfile
WORKDIR /srv
WORKDIR api
WORKDIR logs
RUN pwd
```

Expected directory: `/srv/api/logs`, because relative WORKDIR values are appended to the previous WORKDIR. Absolute paths reset the location.

**Practical rule:** use an absolute `WORKDIR /app` unless you intentionally build a directory hierarchy. It is easy to make a future maintainer miss a relative directory change.

### 2.3 Relationship to `COPY`, `RUN`, `CMD` and `ENTRYPOINT`

`WORKDIR` changes path resolution for later instructions, including relative `COPY`/`ADD` destinations, and sets the container process's default cwd.

```dockerfile
WORKDIR /app
COPY application.py .
RUN ls -l application.py
CMD ["python3", "application.py"]
```

**These lines only illustrate path behavior**; the image also needs an appropriate Python runtime. A working directory does not install languages or grant permissions.

### 2.4 Runtime override

```bash
podman run --rm --workdir /tmp nonroot-demo pwd
```

`--workdir` can override the image's working directory for an individual run. Thus image metadata is a **default**, not an unchangeable guarantee.

### 2.5 Hidden pitfall: `WORKDIR` and ownership

When `WORKDIR /app` creates a new directory during build it is usually owned by the identity then in effect, often root. Later changing to `USER appuser` does **not** rewrite filesystem ownership. The user may be able to **enter** `/app` but still not write to it. That's why this exercise does `chown -R appuser:appuser /app` **before** `USER appuser`.

---

## 3. Linux permissions: the underlying system

### 3.1 Process identity is numeric

Linux uses numeric UID/GID values. The name `appuser` is a human-readable lookup in `/etc/passwd`. Two containers can both have an account named `appuser` but with different UIDs. For mounted volumes, it's the numeric identities and their mappings that matter.

Useful commands:

```bash
id
id -u
id -g
whoami
ls -ld /app
stat -c '%u:%g %A %n' /app
```

### 3.2 Read, write and execute in a directory

- `r` on a directory: generally lets the process list names.
- `w` plus `x` on a directory: allows creating/removing directory entries, subject to extra controls.
- `x` on a directory: allows traversing it to access known paths.

Imagine:

```text
drwxr-xr-x 2 root root ... /app
```

A non-root user can typically read/traverse `/app` but cannot write there. In contrast:

```text
drwxr-xr-x 2 appuser appuser ... /app
```

`appuser` can create files inside it, while other users cannot (assuming no ACL, immutable flag, read-only mount, SELinux or other restrictions change that).

### 3.3 `chmod` vs `chown`

- `chmod` edits permission bits/modes, e.g. `chmod 750 /app`.
- `chown` edits owner/group, e.g. `chown appuser:appuser /app`.

Overly broad fixes such as `chmod -R 777 /app` can expose data and are rarely justified. Prefer targeted ownership and minimal group permissions.

### 3.4 Ownership is not authentication

Creating `appuser` in `/etc/passwd` does not create a cloud identity, grant AWS permissions, or isolate the network. It determines the container process's Linux identity and interacts with kernel access checks. Distinguish Linux filesystem permissions from AWS IAM roles, Kubernetes service accounts and application login permissions.

---

## 4. `USER`: default identity for build and runtime

### 4.1 Build-time vs runtime

```dockerfile
RUN useradd -u 1001 -m appuser
USER appuser
RUN whoami
```

The final `RUN` should execute as `appuser`, because `USER` affects **subsequent `RUN` instructions** and the configured default for running the resulting image.

If you place `USER appuser` **before** installing packages or changing root-owned directories, the later privileged build actions will often fail. Build the filesystem with required permissions first, then drop privileges for application execution.

### 4.2 Named user or numeric UID?

```dockerfile
USER appuser
# or
USER 1001
# or
USER 1001:1001
```

Named users improve readability and map via `/etc/passwd`. Numeric IDs can be easier to reason about in CI/Kubernetes, where identity rules may be strict. `USER 1001` alone does not imply group `1001` in every runtime/configuration; be explicit about group access where necessary and verify with `id`.

### 4.3 Runtime overrides exist

```bash
podman run --rm --user root nonroot-demo id
```

This changes the process identity for **that run** (subject to runtime and policy constraints). Therefore `USER appuser` is a sensible secure default, not a cryptographic lock against an operator who controls Podman and chooses to override it.

### 4.4 Why the verification files are in `/tmp`

In the exercise:

```dockerfile
RUN whoami > /tmp/user.log && ls -ld /app >> /tmp/user.log
```

`/tmp` conventionally permits unprivileged processes to create temporary files. The build records observations in a place `appuser` can write without needing to alter privileged system paths. The resulting `/tmp/user.log` is part of the **image built by that instruction**; it is **not a live runtime identity feed**. Always run `podman run --rm nonroot-demo id` to observe the runtime user too.

---

## 5. Explain the actual teaching Containerfile, line by line

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal
```

Uses Red Hat's compact UBI 9 base. Compact is useful, but means fewer tools (e.g. `ps`) may exist. For maximal reproducibility, review and pin a tested digest instead of relying only on a floating repository name.

```dockerfile
LABEL maintainer="Hafiz Mohammad Sunasara"
```

Adds metadata only. It does not change privilege, file ownership or application execution.

```dockerfile
WORKDIR /app
```

Sets the default directory for later instructions and runtime; creates `/app` when absent.

```dockerfile
RUN pwd > /tmp/workdir.log && whoami >> /tmp/workdir.log
```

Captures the build-time directory and current build user **before** the user switch.

```dockerfile
RUN microdnf install -y shadow-utils && \
    microdnf clean all && \
    useradd -u 1001 -d /home/appuser -m appuser && \
    chown -R appuser:appuser /app
```

Uses `microdnf` (UBI Minimal's package manager), installs `useradd`, creates UID 1001 and transfers ownership to the dedicated account. `&&` stops later actions if an earlier action fails. Doing the install/cleanup in one RUN can avoid leaving package cache in earlier layers.

```dockerfile
USER appuser
```

Applies the application identity as the default for future build and runtime commands.

```dockerfile
RUN whoami > /tmp/user.log && ls -ld /app >> /tmp/user.log
```

Checks build-time identity and filesystem ownership *after* switching. A label, name or expected log is not as strong as observing `podman run` exit codes and identity.

---

## 6. Root vs rootless: two axes, not synonyms

Consider this matrix:

| Podman host mode | Container process identity | Meaning |
| --- | --- | --- |
| Rootful Podman | `root` | Higher-risk combination; container isolation still applies but host daemon/runtime runs with host privileges. |
| Rootful Podman | `appuser` | Container app drops UID 0; host runtime still rootful. |
| Rootless Podman | `root` | UID 0 *inside a user namespace*, typically mapped to an unprivileged host UID. |
| Rootless Podman | `appuser` | Unprivileged host execution plus non-root app default: helpful defense in depth. |

### 6.1 What mapping means

A user namespace can translate UIDs. For example, an unprivileged host user might map to container UID 0 in the namespace. That container-root process does not thereby gain full host-root access.

Observe mapping only in a disposable test environment:

```bash
podman info --debug
podman unshare cat /proc/self/uid_map
podman unshare cat /proc/self/gid_map
```

Interpret the actual `uid_map` values; do not assume the screenshot from one lab applies to a different host.

### 6.2 Why bind mounts can be tricky

Suppose a host directory belongs to UID 1000 and the container process is UID 1001. Without appropriate user-namespace mapping and ownership, writes to a mounted directory may fail even if `chown /app` succeeded **inside the image**. A bind mount overlays the image's `/app` at runtime and exposes the mount's own permissions. Investigate the mount and mapping rather than changing the image's folder and expecting all volumes to work.

`--userns=keep-id` is a tool for intentionally matching the host caller UID inside a rootless container in supported configurations. It isn't a default fix for every permission problem; document mappings and test on your host.

---

## 7. Security: what does non-root actually prevent?

### 7.1 Least privilege

An application that only reads its code and writes files to `/app/data` should not be granted the ability to modify `/etc`, install packages at runtime, or write under `/root`. Restrict its identity and mounts to what it needs.

### 7.2 Threat scenario

An attacker finds a vulnerability in a web endpoint and gains code execution inside the app process. If the process is root, it may have broader access to in-container files and privileged operations (still constrained by namespaces, dropped capabilities, seccomp, LSM, mounts, policy and runtime). As `appuser`, it generally cannot write root-owned paths and its writable surface is smaller.

**Important:** Non-root is *not* enough if you mount host secrets, give broad filesystem permissions, attach privileged devices, or expose dangerous host sockets. Rootless/non-root containers still require safe network, supply chain, secrets and host configuration.

### 7.3 Why `--privileged` is a dangerous shortcut

`--privileged` can loosen multiple isolation controls. It may make a broken exercise appear to work while destroying the signal you intended to test. Use targeted debugging first. The same applies to disabling SELinux globally.

### 7.4 Other production hardening controls

A non-root image becomes more useful alongside:

- `--cap-drop=ALL` plus selectively restored required capabilities.
- `--read-only` root filesystem and a narrow writable volume/tmpfs.
- resource constraints (CPU/memory/PID limits).
- image provenance, digest pinning, scanning and timely patching.
- secret injection rather than baked-in tokens.
- ingress/network policies and TLS.
- monitored readiness, health checks, logs and alerting.

Every measure should be tested against actual application behavior—security that prevents legitimate operation is a reliability failure too.

---

## 8. Test like an engineer: positive and negative cases

The goal is not just to see an expected-looking string. A valid claim needs a command, observable result and interpretation.

| Claim | Test | Correct interpretation |
| --- | --- | --- |
| Working directory configured | `podman run --rm workdir-demo pwd` | Runtime cwd equals `/app`. |
| Image defaults to non-root | `podman image inspect ...` + `id -u` | Metadata plus observed process identity. |
| App can write its assigned path | `touch /app/testfile` | Process has expected access. |
| App cannot write private root path | `touch /root/blocked-file` | Denial supports least-privilege argument, in context. |
| Process remains non-root while running | `podman top`, `podman exec id` | Live process-level observation. |
| `/sys` access denied | `touch /sys/kernel/profiling` | May reflect read-only mount, not solely a UID restriction. |

### 8.1 Why exit codes matter

Unix commands commonly signal success with exit status `0` and failure with nonzero exit status. A screenshot showing only a command without its exit status may be ambiguous. Automated checks can capture failures and explicitly consider a **known negative test** a success.

### 8.2 How `verify.sh` works

The script builds both images, evaluates required strings/UID, proves permitted writes under `/app`, and expects `/root` write to fail. It exits nonzero if an assertion fails. It deliberately does **not** run any destructive broad image-pruning commands.

**Don't invent verification evidence:** if a course UI indicates completion but terminal logs were not saved, label the UI screenshot as course status and the commands here as reproducible instructions, not historically observed logs.

---

## 9. OpenShift/Kubernetes: the harder edge case

### 9.1 A fixed `USER appuser` isn't the whole story

OpenShift commonly runs workload processes with UIDs assigned by policy. Depending on the security context, this may not equal your image's named `appuser` (UID 1001). Images that require one fixed UID to own all writable directories can fail when launched under an arbitrary UID.

### 9.2 A common adaptable directory pattern

Depending on platform policy, images may grant the **root group** access to writable app directories and align group permissions with user permissions, allowing the assigned arbitrary UID to operate through group `0` where the platform grants that membership:

```dockerfile
RUN chgrp -R 0 /app && chmod -R g=u /app
```

**Do not blindly run this on sensitive files or entire system directories.** Limit changes to the specific directories your app must read/write and verify the actual Pod's `securityContext`, UID, GID and mounted-volume permissions. Also consider runtime-created data and non-root-friendly listening ports.

This lab uses a named `appuser` because that is the course learning objective; it is **not** claiming full OpenShift arbitrary-UID compatibility.

### 9.3 Security context vs image USER

Kubernetes/Podman runtime configuration can override image defaults. Running as a particular UID may be mandated by cluster policy. Verify the **deployed process**, not just a Containerfile committed in Git.

### 9.4 A deployment-ready check list

- Is app code readable by the arbitrary runtime UID?
- Are only intended data directories writable?
- Are logs printed to stdout/stderr rather than assuming write access under `/var/log`?
- Does the application need a writable home directory?
- Are ports nonprivileged and permissions compatible?
- Do volume ownership / `fsGroup` / storage classes align with runtime UID?
- Can the app survive restart without assuming ephemeral container-layer files persist?

---

## 10. Better patterns for real application images

### 10.1 Prepare ownership before dropping privileges

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal
WORKDIR /app
RUN microdnf install -y shadow-utils && microdnf clean all && \
    useradd -u 1001 -m appuser && \
    mkdir -p /app/data && chown -R 1001:1001 /app
USER 1001:1001
```

This is a minimal *pattern*. Add your runtime application, command and health checks as appropriate.

### 10.2 `COPY --chown` if copying files

```dockerfile
# Assuming appuser already exists and /app is your WORKDIR
COPY --chown=1001:1001 ./config/ /app/config/
```

In compatible builders this sets ownership while copying, avoiding a later broad recursive `chown` layer. Relative paths and source ownership must be checked. Do not assume this makes host bind mounts writable—the mount's own permissions still apply.

### 10.3 Narrow write paths

Not everything in `/app` needs to be writable by the service. Prefer read-only code/config and a dedicated `/app/data` or mounted storage location, with minimal write permissions. That limits opportunities for a compromised application to change its own executable code.

### 10.4 Supply-chain reproducibility

- `ubi9/ubi-minimal` is a moving reference.
- A version tag reduces unintended jumps but can sometimes be republished.
- A tested digest gives stronger binary reproducibility.
- Digest pinning does not guarantee security forever; patch intentionally and rebuild regularly.

---

## 11. Debugging playbooks

### Scenario A — Build succeeds; app can't write `/app`

1. Observe identity: `podman run --rm nonroot-demo id`.
2. Observe directory: `podman run --rm nonroot-demo ls -ld /app`.
3. Check whether a runtime mount replaced `/app`.
4. Verify host mount UID/GID mapping and SELinux labels if applicable.
5. Make the smallest targeted ownership or group permission adjustment.
6. Re-run the write test and document which specific change fixed it.

### Scenario B — `useradd: command not found`

1. Confirm `FROM` image and package manager.
2. Check installation: `microdnf install -y shadow-utils`.
3. Inspect the full build log for repository/network errors.
4. Rebuild. Don't solve by deleting `USER` if the security goal is non-root runtime.

### Scenario C — UID collision during `useradd`

1. Inspect `/etc/passwd` in the relevant base image.
2. Pick an unused UID or reuse an existing suitable application account.
3. Update ownership, verification steps and documentation to match.

### Scenario D — `ps -ef` not available

Use `podman top <container>` from the host. Slim container bases omit tools to reduce attack surface and size. Optionally add process utilities in a **debug** image, but don't enlarge production images for an occasional inspection command without thinking.

### Scenario E — Permission denied under `/sys`

Check mount restrictions rather than assuming user configuration. `/sys` is a kernel pseudo-filesystem, not a normal writable application directory. Prefer `/root` negative test paired with `id` and `/app` positive test.

### Scenario F — Rootless mismatch with bind-mounted host files

Inspect `podman unshare cat /proc/self/uid_map` and the host directory's numeric owner. Decide whether mapped ownership, an intentionally configured `--userns=keep-id`, or a named volume is appropriate. Never mask the issue with blanket world-writable permissions.

---

## 12. Oral-exam / interview questions with model answers

**Q1. `WORKDIR` vs `RUN cd /app`?**  
A: `WORKDIR` changes persistent image configuration for subsequent instructions and runtime. `RUN cd` changes only the executing shell of that one build instruction.

**Q2. Does `USER appuser` automatically make `/app` writable?**  
A: No. Linux filesystem ownership and permissions are separate. Use targeted `chown`, group permissions or mount configuration.

**Q3. Why create UID 1001?**  
A: To use a dedicated non-root identity. There is no magical security property in the number 1001; the key is that it is not root and file access matches policy.

**Q4. What's wrong with `chmod 777 /app`?**  
A: It grants overly broad access and violates least privilege; use minimal necessary ownership/modes.

**Q5. Is container root the same as host root?**  
A: Not necessarily. Rootless Podman commonly runs UID 0 inside a user namespace mapped to an unprivileged host identity. Rootful/privileged setups are different.

**Q6. What does `--user root` do?**  
A: Overrides the image's default user for that runtime invocation, within the runtime's permission model.

**Q7. Why might `/sys/kernel/profiling` reject writes even as root?**  
A: Pseudo-filesystem mount restrictions and read-only settings may apply independently of the UID.

**Q8. What if OpenShift assigns an arbitrary UID?**  
A: The image must not assume its named user exists as the runtime UID or owns the volume. Engineer file permissions and security context for that deployment model.

**Q9. How do you prove a test worked?**  
A: Capture command, exit status, actual output and environment; distinguish expected behavior from observed behavior.

**Q10. Is a completion icon proof that every hardening scenario passed?**  
A: No. It supports course progression, not individual runtime command outcomes.

---

## 13. Hands-on mastery exercises

Mark each item **verified** only after running it and recording the result. These are proposals, not claimed outcomes.

- [ ] Change `WORKDIR /app` to `/srv/recoverops` and predict/verify `pwd`.
- [ ] Use two relative `WORKDIR` instructions and verify the resulting path.
- [ ] Remove `chown /app` and document exactly which write test fails, then restore it.
- [ ] Override the user with `podman run --rm --user root ... id`; compare.
- [ ] Compare `--read-only` runtime behavior with and without a writable volume.
- [ ] Run the `verify.sh` script and save actual exit codes/logs.
- [ ] Test the image on a rootless VM with a bind mount owned by another UID.
- [ ] Explore `podman unshare` and interpret a real UID mapping.
- [ ] Design an OpenShift-compatible writable directory policy for arbitrary UIDs.
- [ ] Pin and test a specific base image digest, then capture its digest in the runbook.

## 14. One-page recall sheet

| Remember | Why |
| --- | --- |
| `WORKDIR /app` | Predictable current directory for build/runtime. |
| `USER appuser` | Image defaults to a dedicated non-root identity. |
| `useradd -u 1001 -m appuser` | Creates a named account at known UID. |
| `chown -R appuser:appuser /app` | Grants intended ownership; does not touch host volumes. |
| `id`, `whoami`, `ls -ld` | Verify identity and directory permissions. |
| `podman top` | Inspect container processes from host. |
| `/root` negative test | Demonstrates restricted access under normal Unix permission checks. |
| `/sys` test | Often tests container mounts too; not proof of UID alone. |
| `--user` | Overrides configured runtime user. |
| rootless Podman vs `USER` | Separate mechanisms and threat boundaries. |
| arbitrary UID in OpenShift | Requires deliberate ownership and group permission design. |

### Final engineering principle

**Build-time success is only the start. Secure container engineering means proving the running process has exactly the access it needs—and no more—on the actual target platform.**

## Further reading

- [Dockerfile reference: `WORKDIR`, `USER`](https://docs.docker.com/reference/dockerfile/)
- [Red Hat UBI Minimal package management](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/building_running_and_managing_containers/assembly_adding-software-to-a-ubi-container_building-running-and-managing-containers)
- [Podman user namespaces](https://docs.podman.io/en/v4.4/markdown/options/userns.container.html)
- [OpenShift image permissions and arbitrary UIDs — Red Hat Developer](https://developers.redhat.com/articles/2024/10/01/build-container-images-openshift-using-podman-gitlab-runner)
