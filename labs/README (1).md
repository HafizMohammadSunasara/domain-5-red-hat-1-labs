# Lab 04 — Setting `WORKDIR` and `USER` Instructions

**Domain 5 · Linux and Open Source · Red Hat 1**  
**Topic 2:** Red Hat Certified Specialist in Containers  
**Learning environment:** Podman, Red Hat UBI 9 Minimal  
**Maintainer:** Hafiz Mohammad Sunasara  
**Session date:** 23 October 2026  
**Progress:** Learner reports the lab complete; a course-interface completion indicator is retained. Full terminal execution output was **not provided** with this submission.

> **Engineering question:** How do we make a container start in the correct directory, use a least-privileged identity, and verify that access controls behave as intended?

[Deep technical explanation](DEEP-DIVE.md) · [Course screenshot](evidence/01-course-platform-completion.png) · [Proof limitations](evidence/README.md) · [Test script](verify.sh) · [Topic 2 parent](../)

## 1. Objectives and learning outcomes

By completing this exercise, a learner should be able to:

1. Set and verify a build/runtime working directory using `WORKDIR`.
2. Create a dedicated application user with UID `1001` using `shadow-utils`.
3. Transfer application-directory ownership using `chown`.
4. Set the image's default user with `USER` and verify its UID.
5. Contrast expected success and expected permission-denial cases.
6. Explain what this protects against—and what it **does not** protect against.

## 2. Important terminology

| Term | Practical meaning |
| --- | --- |
| **Image** | Reusable, immutable-by-convention template built from a Containerfile. |
| **Container** | A running or stopped instance of an image. |
| **`WORKDIR`** | Sets the default directory for later build instructions and container startup, unless overridden. |
| **`USER`** | Sets the default user (name/UID) and optionally group for subsequent `RUN` and runtime commands. |
| **UID / GID** | Numeric Linux identity / group used for permissions. |
| **`chown`** | Changes who owns a filesystem path. |
| **Rootless Podman** | Podman started by a non-root host user, typically using user namespaces. Distinct from a non-root application `USER`. |

For an analogy: `WORKDIR` decides **which room the application enters**; `USER` decides **which keys it carries**. `chown` makes sure the keys match the files it is supposed to use.

## 3. Project layout

```text
lab-04-workdir-and-user/
├── README.md                    # Lab commands, checks, troubleshooting
├── DEEP-DIVE.md                 # Beginner → advanced reference
├── Containerfile                # Full non-root configuration
├── Containerfile.workdir        # Task 1 root baseline image
├── verify.sh                    # Optional, explicit reproducibility checks
└── evidence/
    ├── README.md                # Scope of the screenshot
    └── 01-course-platform-completion.png
```

Files were reconstructed from the provided course instructions and the earlier guided example. They are **reference/reproduction materials**, not byte-for-byte exports of the cloud lab environment.

## 4. Setup: prerequisites

**Prerequisite check:** Podman must be installed and able to pull the Red Hat UBI image. The course examples use Ubuntu/other Linux hosts, but the image itself is based on RHEL UBI 9 Minimal.

On a Linux host/VM with network access:

```bash
podman --version
mkdir -p ~/container-security-lab
cd ~/container-security-lab
```

For this repository, copy `Containerfile`, `Containerfile.workdir` and `verify.sh` into that working directory, or run the following from the lab's repository folder.

**Reproducibility notice:** The instructional base image is `registry.access.redhat.com/ubi9/ubi-minimal` with no version/digest pin. A future build may receive a newer UBI 9 patch release. For a controlled production pipeline, select, review and pin a tested image digest.

## 5. Task 1 — `WORKDIR`: set the default directory

**Open:** [`Containerfile.workdir`](Containerfile.workdir)

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal
LABEL maintainer="Hafiz Mohammad Sunasara"
WORKDIR /app
RUN pwd > /tmp/workdir.log && whoami >> /tmp/workdir.log
```

**Reasoning:** `WORKDIR /app` sets the directory seen by later `RUN` instructions and the image's default runtime command. The directory is created if necessary. Nothing here changes the user, so the baseline build should run under the base image's default identity (in this exercise: `root`). `RUN` executes at image build time; its outputs are stored as a file for inspection.

Build and verify:

```bash
podman build -f Containerfile.workdir -t workdir-demo .
podman run --rm workdir-demo cat /tmp/workdir.log
podman run --rm workdir-demo pwd
```

Expected build-time log and runtime working directory:

```text
/app
root
```

```text
/app
```

**If `whoami` is unavailable:** use `id -un` in the Containerfile and rebuild; minimal images may omit some utilities.

## 6. Task 2 — Create and select a non-root user

**Open:** [`Containerfile`](Containerfile)

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

Explain each line:

1. `microdnf install -y shadow-utils`: installs tools such as `useradd` in a UBI Minimal image.
2. `microdnf clean all`: removes package-manager caches from the build layer.
3. `useradd -u 1001 ... -m appuser`: creates an account with UID `1001` and a home directory.
4. `chown -R appuser:appuser /app`: makes the working directory owned by the application identity.
5. `USER appuser`: switches subsequent build steps and the default runtime user.
6. The final `RUN` saves identity and directory ownership to `/tmp/user.log` **during the build**.

Build and verify:

```bash
podman build -f Containerfile -t nonroot-demo .
podman run --rm nonroot-demo cat /tmp/user.log
podman run --rm nonroot-demo id
podman run --rm nonroot-demo whoami
podman image inspect nonroot-demo --format '{{.Config.User}}'
```

Example expected format (the timestamps/permission bits can differ):

```text
appuser
drwxr-xr-x ... appuser appuser ... /app
```

Default username: `appuser`. Expected UID: `1001`. `podman image inspect` should report `appuser` as the configured user (the actual value is not an independent test that all filesystem permissions are correct).

Confirm that a non-root application can write **where intended**:

```bash
podman run --rm nonroot-demo touch /app/testfile
```

An exit code of `0` indicates success. With `--rm`, this test file disappears with the container instance; it does not modify the source image.

To report the result explicitly:

```bash
if podman run --rm nonroot-demo touch /app/testfile; then
  echo "PASS: non-root user can write to /app"
else
  echo "FAIL: investigate /app permissions"
fi
```

## 7. Task 3 — Validate security restrictions

### 3.1 Negative test: unprivileged path

```bash
podman run --rm nonroot-demo touch /root/blocked-file
```

**Expected:** a non-zero exit code and a permission-denied message. This is a **successful negative security test**, not a lab failure. A visible error by itself is not proof of *why* access was denied; verify runtime UID first.

```bash
podman run --rm nonroot-demo id -u
# Expected: 1001
```

The original course instruction also asks:

```bash
podman run --rm nonroot-demo touch /sys/kernel/profiling
```

**Interpret carefully:** `/sys` is generally a pseudo-filesystem mounted with restrictions (often read-only) inside containers; an error there does not by itself prove that `USER` is non-root. Pair the test with `id -u`, ownership checks and a normal filesystem permission test such as `/root/blocked-file`.

### 3.2 Inspect a real running process

```bash
podman run -d --name testuser nonroot-demo sleep 300
podman top testuser
podman exec testuser id
podman rm -f testuser
```

Look for UID `1001` / `appuser`. The host-side `podman top` is useful because slim UBI images may not include `ps`; if you need `ps` inside the image you must explicitly add the relevant package. If the example container has already exited, inspect its logs/state and rerun it with a long-lived foreground process.

## 8. Task 4 — Compare root and non-root

```bash
podman run --rm --user root workdir-demo whoami
podman run --rm nonroot-demo whoami
```

Expected comparison:

| Test | Expected identity |
| --- | --- |
| `workdir-demo` with explicit `--user root` | `root` |
| `nonroot-demo` using its default `USER` | `appuser` |

**Security insight:** Root **inside** a rootless Podman container is not automatically root **on the host**; host privilege and container UID are governed by namespaces/mappings and other isolation layers. Still, non-root inside the container is a valuable defense-in-depth default.

## 9. Optional end-to-end verifier

The included [`verify.sh`](verify.sh) rebuilds both examples, checks `/app`, `root` vs `appuser`, UID `1001`, permitted writes and expected rejection of a `/root` write. It does **not** delete images or call `podman image prune`.

```bash
bash verify.sh
```

**Warning:** This verifier actually builds images and runs containers. Its success is not implied by its inclusion here; run it and retain the output if you want stronger reproducible evidence.

## 10. Troubleshooting matrix

| Symptom | Likely cause | Safe diagnosis/action |
| --- | --- | --- |
| `whoami: command not found` | Minimal base image lacks command | Try `id -un` or install needed package during build. |
| `useradd: command not found` | `shadow-utils` missing | Verify `microdnf install -y shadow-utils` succeeded before calling `useradd`. |
| `useradd: UID 1001 is not unique` | Base image already has that UID | Inspect `/etc/passwd`; pick a free UID and update assertions/documentation. |
| `microdnf` fails | Registry, DNS, repository access or package issue | Check connectivity, image tag/repositories and full build log. |
| `/app` permission denied | Directory or nested files owned by root | Inspect `ls -ld /app`; use `chown` or more targeted file ownership. |
| `/root` write fails | Expected non-root restriction | Record exit status and pair with identity test. |
| `/sys/...` says read-only | Normal container mount restrictions | Don't infer UID from this result alone. |
| `ps: command not found` | Minimal image omits process tools | Use `podman top testuser` from host. |
| `sleep` container exits | Missing command, error, or elapsed duration | Use `podman logs testuser`, `podman inspect testuser`. |
| Rootless mapping issues | Host subordinate UID/GID configuration | Inspect `podman info --debug`, `podman unshare cat /proc/self/uid_map`. |

Avoid automatically adding `--privileged`, disabling SELinux, or running the whole image as root to silence permission errors. That defeats the purpose of this lab.

## 11. Evidence and completion integrity

### What is actually evidenced?

The course-interface screenshot documents the LMS completion indicator. It **does not** display the full build terminal, image inspect output or protected-path test results. The commands and expected outputs above are a **reproducible runbook**, not invented execution transcripts.

| Evidence type | This delivery |
| --- | --- |
| Learner's report that Lab 04 is finished | Yes — user reported completion. |
| LMS/course UI completion indicator | Yes — [original screenshot](evidence/01-course-platform-completion.png). |
| Original terminal build logs and `podman run` outputs | **Not supplied** in this message. |
| Tested execution of these reconstructed files | **Not performed here.** |

See the [evidence policy](evidence/README.md). Screenshots should never be described as proving commands they do not show. Keep real logs/screenshots if you later rerun the verifier.

## 12. Cleanup (optional, only when no longer needed)

```bash
podman rm -f testuser   # only if this lab's container still exists
podman rmi workdir-demo nonroot-demo
```

**Do not** run broad `podman image prune -a` or `rm -rf` against an unverified path; those operations could remove unrelated working assets. Keep lab documentation and evidence in GitHub.

## 13. Next experiments

### A five-minute revision checklist

Before explaining this lab to another engineer, make sure you can answer these questions without notes:

1. Does `WORKDIR` change the runtime UID?
2. Why can a process fail to write to `/app` even when `WORKDIR /app` exists?
3. When does a Dockerfile `RUN` execute compared to `podman run`?
4. What changes after adding `USER appuser`?
5. Why isn't `touch /sys/...` an adequate test of non-root permissions by itself?
6. How is rootless Podman different from a non-root process inside a container?
7. Why may an arbitrary OpenShift UID require group-based permission design?

Answers and detailed reasoning are explained in [DEEP-DIVE.md](DEEP-DIVE.md).

- Compare `podman run --rm --user 1001 nonroot-demo id` with image default `USER`.
- Explore `--userns=keep-id` and `podman unshare` to understand host/container UID mapping.
- Test read-only container rootfs: `podman run --rm --read-only nonroot-demo id`.
- Study **arbitrary UIDs in OpenShift**; an image pinned to a named user may require extra group ownership and permission design.
- Rebuild with a reviewed digest-pinned UBI image after choosing a tested release.

## References

- [Dockerfile instruction reference — `WORKDIR` and `USER`](https://docs.docker.com/reference/dockerfile/)
- [Red Hat documentation — package management for UBI Minimal](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/building_running_and_managing_containers/assembly_adding-software-to-a-ubi-container_building-running-and-managing_containers)
- [Podman user namespace options](https://docs.podman.io/en/v4.4/markdown/options/userns.container.html)
- [Red Hat — OpenShift and arbitrary user IDs](https://developers.redhat.com/articles/2024/10/01/build-container-images-openshift-using-podman-gitlab-runner)

---

**Guiding principle:** Give the application a predictable place to run, a predictable identity, and the smallest permissions that still let it operate correctly.
