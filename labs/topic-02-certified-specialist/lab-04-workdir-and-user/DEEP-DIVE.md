# Engineering Deep Dive — `WORKDIR`, `USER` and Non-Root Container Security

**Domain 5 · Red Hat 1 · Topic 2 · Lab 04**  
**Purpose:** A long-term, beginner-friendly engineering reference to understand *what* each directive changes, *why* it matters and *how* to troubleshoot it.

> **Core idea:** A container is a process with an isolated filesystem view and a defined identity. `WORKDIR` establishes where that process starts; `USER` establishes which identity it uses. Reliable containers need both predictable paths and least-privilege permissions.

## 1. First, visualize what is happening

Imagine a Linux server with an application directory and a user account.

- You place your program inside `/app`.
- You create an account called `appuser` with user ID **1001**.
- You give that account ownership of `/app`.
- You start the process as `appuser`, not as `root`.

A Containerfile builds an image that describes this setup. Every new container started from the image gets its own runtime instance of the image filesystem and inherits its configured directory/user unless you override them.

```text
Container image
├── Base filesystem: Red Hat UBI 9 Minimal
├── Working directory: /app
├── Account: appuser (UID 1001)
├── Ownership: /app → appuser:appuser
└── Runtime defaults: cwd=/app, user=appuser
```

**Think like an engineer:** Where will my program read files? What directories must it write? Which user owns them? What happens if an attacker exploits the app? These questions drive the design.

## 2. `WORKDIR` from zero

`WORKDIR /app` sets the current working directory for **subsequent** instructions such as `RUN`, `CMD`, `ENTRYPOINT`, `COPY` and `ADD` when paths are relative, and it defines the image's default working directory at runtime.

### Without `WORKDIR`

A relative file path may depend on the base image's default working directory. Different images and runtime overrides can behave differently.

### With `WORKDIR`

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal
WORKDIR /app
RUN pwd
```

`RUN pwd` executes in `/app`. A container normally also starts there:

```bash
podman run --rm workdir-demo pwd
```

**Important clarifications:**

- `WORKDIR` lives **inside the image**, not on your Windows or Linux host.
- A missing directory is created during the build.
- `WORKDIR` is not the same as `COPY` (moving content) or `VOLUME` (mounting/persisting storage).
- `WORKDIR /app` says nothing about who is allowed to write in `/app`.
- `WORKDIR /app` followed by `WORKDIR logs` uses the relative path `/app/logs`; absolute paths begin with `/`.

### Why this is useful

A predictable directory avoids fragile scripts like `cd /wherever && ./start.sh`. It also helps teammates reproduce builds and reduces accidental dependence on image defaults.

## 3. `USER` from zero

Linux associates processes with **numeric** user IDs (UID) and group IDs (GID). Display names like `appuser` are conveniences resolved through files such as `/etc/passwd`.

```dockerfile
USER appuser
```

This sets the identity for later build commands that run in the image and the container's default process identity. It does **not** automatically create the user. That's why we first execute:

```bash
useradd -u 1001 -d /home/appuser -m appuser
```

### Break down the command

- `useradd`: creates the account in the **image filesystem**.
- `-u 1001`: assign UID 1001.
- `-d /home/appuser`: use that home path in the account record.
- `-m`: create a home directory.
- `appuser`: login name.

Ubuntu and RHEL may differ in package managers and defaults; this lab uses Red Hat UBI Minimal and `microdnf` to install `shadow-utils`.

### Why numeric IDs matter

File permissions are checked against numeric IDs. Even when the **name** printed by `whoami` changes, a filesystem still enforces permissions for UIDs/GIDs. For containers that run with arbitrary users (a common OpenShift constraint), rely on portable permission design rather than assuming one fixed username everywhere.

## 4. Ownership and permissions: `chown`, `chmod`, and write access

Linux permission checks typically involve:

```text
r = read    w = write    x = execute/traverse

Owner | Group | Others
  rwx |   r-x |   r-x    → example directory mode 755
```

For directories, `x` usually means **traverse/search**. It is not the same as the `x` bit on a script or binary.

A directory created by root is commonly owned by root. Switching to `USER appuser` without changing ownership may leave it unable to write.

```dockerfile
RUN chown -R appuser:appuser /app
USER appuser
```

The **order** matters: changing `/app` ownership is typically a root-level image-build operation, so do it **before** switching to the unprivileged account.

### Compare two scenarios

**Broken pattern:**

```dockerfile
WORKDIR /app
USER appuser
RUN touch /app/data.txt
```

This may fail if `/app` is owned by root and not group-/world-writable.

**Working pattern:**

```dockerfile
WORKDIR /app
RUN chown -R appuser:appuser /app
USER appuser
RUN touch /app/data.txt
```

Do not solve the broken case with `chmod -R 777 /app`. It opens write access to more identities than necessary and weakens the least-privilege goal.

### What does `-R` mean in `chown -R`?

Recursive: it also changes ownership of contained files/directories. On very large directory trees, indiscriminate recursion can lengthen builds and make ownership changes harder to review. Apply it only to intended paths.

## 5. Build-time state vs runtime state

This confuses many learners, so distinguish them explicitly.

```dockerfile
RUN pwd > /tmp/workdir.log
```

`RUN` executes while **building** the image and saves a file in an image layer.

```bash
podman run --rm workdir-demo cat /tmp/workdir.log
```

The container reads that file **at runtime**. The `RUN` instruction isn't re-executed merely because a container starts.

Similarly:

```dockerfile
USER appuser
RUN whoami > /tmp/user.log
```

The second `RUN` happens at build-time with that user. It proves what identity the **build step** was configured to use. To validate runtime, execute `podman run --rm nonroot-demo whoami` separately.

## 6. A security experiment: why should `/root` fail?

A Linux non-root account normally cannot write arbitrary files under `/root`. Thus:

```bash
podman run --rm nonroot-demo touch /root/blocked-file
```

should fail with a permission-related error in this design.

This result is useful only alongside independent identity confirmation:

```bash
podman run --rm nonroot-demo id
podman run --rm nonroot-demo whoami
podman image inspect nonroot-demo --format '{{.Config.User}}'
```

**Interpretation:** `USER` controls the default account; filesystem ownership and mode bits enforce what it can access.

### Why `/sys/kernel/profiling` is a weaker isolated test

`/sys` represents kernel interfaces exposed into the container. It may be mounted read-only or restricted by separate security policies and namespace rules. Even a root process in a container can fail to write there. A denial isn't by itself proof that the image is running as a non-root user.

## 7. Root in a container is not necessarily root on the host

There are at least two different questions:

1. **What identity does the process have inside the container?** Controlled by image `USER`, runtime `--user` override and user namespaces.
2. **Is Podman itself running rootless on the host?** Controlled by how you launch Podman and its host-side user namespace/storage configuration.

They are **not interchangeable**.

| Scenario | Container-side process identity | Host-side Podman mode |
| --- | --- | --- |
| Rootful Podman + no `USER` | Often root (UID 0) | Rootful |
| Rootless Podman + no `USER` | Often root **inside the container namespace**, mapped to an unprivileged host UID | Rootless |
| Rootless Podman + `USER appuser` | Non-root UID 1001 inside namespace | Rootless |
| Any Podman + runtime `--user 0` | Overrides image identity to root **inside container** | Rootless/rootful depends on host invocation |

Non-root `USER` helps reduce unnecessary privileges within the container, but it does not replace least-capability policies, safe mounts, regular patching, seccomp, SELinux/AppArmor, secrets management, or network restrictions.

## 8. OpenShift-specific design considerations

Red Hat OpenShift commonly runs workloads subject to Security Context Constraints and may assign an **arbitrary non-root UID**. An image hardcoded to UID 1001 can be useful for learning, but it doesn't guarantee compatibility with every OpenShift policy.

For production-style images, consider:

- Which directories must be writable, and which can remain read-only?
- Can a random UID access those directories via appropriate group permissions (often group 0 in OpenShift-oriented images)?
- Are all files that need access readable/traversable by that user?
- Does the application rely on a specific `/etc/passwd` entry or fixed home folder?
- Does it need privileged ports, capabilities, a writable root filesystem or custom filesystem mounts?

**Key principle:** Design for the minimum required privileges **and** the runtime's identity policy, not just for one successful local run.

## 9. Reproducibility and supply chain

The course uses:

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal
```

That is convenient for learning but does not pin a specific image digest. The registry image behind a moving tag may change over time. More reproducible builds select a reviewed version or immutable digest and record package versions where feasible.

Installing packages during image build also depends on available repositories at that moment. A reproducible source file alone is **not** enough to guarantee byte-for-byte identical images in every environment.

Security priorities in real images include: trusted image origin, supported base, regular vulnerability updates, least-privilege `USER`, minimal packages and predictable filesystem permissions.

## 10. Common failure scenarios and how to reason about them

### Scenario A — `useradd` not found

**Likely cause:** `shadow-utils` isn't installed (or failed to install).

**Investigate:** Inspect `microdnf` output; check registry connectivity and package availability; don't assume the package command succeeded.

### Scenario B — Cannot write to `/app`

**Likely cause:** `/app` still owned by root, or volume mount ownership differs from image ownership.

**Investigate:**

```bash
podman run --rm nonroot-demo id
podman run --rm nonroot-demo ls -ld /app
```

**Fix:** Set proper ownership in the build or configure mounted storage permissions for the runtime identity. `chown` in an image **does not rewrite** ownership on a separately mounted host volume.

### Scenario C — `ps -ef` missing

**Likely cause:** minimal image doesn't include `procps-ng`.

**Safer diagnostic:**

```bash
podman top testuser
podman exec testuser id
```

Installing an entire tool suite solely for one validation command is usually unnecessary.

### Scenario D — Rootless Podman fails before any build step

**Possible causes:** nested lab restrictions, unavailable subordinate UID mappings, overlay storage configuration or privilege limitations.

**Investigate:** Exact error text, `podman info`, user namespace setup and storage settings. **Do not** jump straight to `sudo`, `--privileged` or disabled SELinux.

### Scenario E — `Permission denied` in `/sys`

Could be due to a read-only mount/kernel restriction, regardless of `USER`. Use the `/root` and identity tests to separate explanations.

### Scenario F — Permissions change when adding a bind mount

Container image ownership and host filesystem ownership can differ, especially under rootless user namespace mappings. Inspect mount modes, labeling, user namespace mappings and host path ownership before changing permissions blindly.

## 11. Practical exercises to strengthen understanding

**Exercise 1 — Break it safely:** Make `/app` root-owned, retain `USER appuser`, then run `touch /app/testfile`. Observe the failure and use `ls -ld /app` to explain it. Rebuild with `chown` and recheck.

**Exercise 2 — Override identity:** Run:

```bash
podman run --rm --user 0 nonroot-demo id
```

Compare with the default run. Explain why the image's `USER` is a default that can be overridden if runtime policy permits.

**Exercise 3 — Inspect config:**

```bash
podman image inspect nonroot-demo --format '{{.Config.User}}'
podman image inspect nonroot-demo --format '{{.Config.WorkingDir}}'
```

Explain the relationship between these fields and what happens inside a running container.

**Exercise 4 — Remove write permissions (optional sandbox):** Build an image with `/app` non-writable and determine which operations fail. Do not experiment on shared host paths.

**Exercise 5 — Read-only filesystem:** Try `podman run --rm --read-only nonroot-demo ...` with a purely read-only command. Compare with a command that writes to `/tmp`. A read-only root filesystem is a separate defense, and scratch/tmpfs mounts can be configured when an app needs writable temporary storage.

## 12. Interview-style questions and compact answers

**Q1. What is the difference between `WORKDIR` and `RUN cd /app`?**  
`WORKDIR` persists as build/runtime image configuration. `RUN cd /app` affects only that one shell invocation, not later instructions.

**Q2. Does `USER appuser` create that account?**  
No. You need an existing name or can specify a numeric UID/GID depending on the image and application needs.

**Q3. Why `chown` before `USER`?**  
Because ownership changes usually need elevated privileges during build and should be finished before switching to a less-privileged identity.

**Q4. Why does an unprivileged app still sometimes run successfully without `chown`?**  
It might only read files, or the directory could already have suitable group/other permissions.

**Q5. Is rootless Podman the same as a non-root application user?**  
No. Rootless relates to host execution and user namespaces; `USER` sets the container process identity.

**Q6. Does a `Permission denied` message always prove non-root security?**  
No. Read-only mounts, capabilities, filesystem modes, SELinux and other controls can produce the same error.

**Q7. Why prefer numeric UID checks?**  
Kernel permissions operate on numeric UID/GID, while usernames are mappings. Numerics are essential for understanding mounted storage and arbitrary UID execution.

**Q8. Can the runtime override `USER`?**  
Often yes with `podman run --user`, subject to runtime policies and deployment security controls.

**Q9. Why is `chmod 777` a bad general fix?**  
It expands write permission to everyone and may create avoidable security exposure.

**Q10. What would you harden next?**  
Combine non-root identities with verified minimal images, capability restrictions, read-only root filesystem where feasible, scoped writable storage, restricted network access and security scanning.

## 13. Quick mental checklist

Before publishing a container image, ask yourself:

- [ ] What is the intended runtime working directory?
- [ ] Which user does the process run as?
- [ ] Which paths need read, write and execute/traverse rights?
- [ ] Does the base image actually contain the required programs?
- [ ] Are directory ownership changes performed before dropping privileges?
- [ ] Have I checked runtime identity and a restricted-operation test?
- [ ] Will this image work with rootless Podman and, if relevant, arbitrary OpenShift UIDs?
- [ ] Is the source/base image version intentionally selected?
- [ ] Is actual evidence distinguished from sample/expected output?

## 14. What this lab proves—and doesn't

The Lab 04 course screenshot indicates completion in the training interface. It **doesn't** provide a command-by-command terminal transcript. The runbook and source files show **how to reproduce** the objectives, but are not a substitute for saved execution results. When new screenshots are available, link them with the exact commands they support.

**Final takeaway:** `WORKDIR` is about *where*. `USER` is about *who*. Ownership/mode bits determine *what that identity can do*. A secure container design needs all three decisions to agree.

---

**Back to lab instructions:** [README.md](README.md) · **Previous lab:** [ADD vs COPY](../lab-03-add-vs-copy/README.md)
