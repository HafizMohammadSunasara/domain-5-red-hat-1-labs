# Lab 03 — ADD vs COPY in Containerfiles

**Domain 5 → Red Hat 1 → Topic 2: Red Hat Certified Specialist in Containers**  
**Maintainer:** Hafiz Mohammad Sunasara · **Lab date:** 22 October 2026  
**Reported status:** Completed by learner; terminal output was not retained after the lab environment was deleted. **Not independently verified from evidence.**

> **The engineering rule:** Prefer `COPY` for ordinary files. Reach for `ADD` only when you intentionally need one of its additional behaviors. Know exactly what enters your build context, what gets baked into image layers, and when cached instructions are invalidated.

## What this lab teaches

1. Copy one local text file with `COPY` and with `ADD`.
2. Demonstrate automatic extraction of a **local** `.tar.gz` archive with `ADD`.
3. Fetch a remote HTTPS file with `ADD` (educational example, **not pinned**).
4. Change a source file and observe how `COPY` and `ADD` interact with build cache.
5. Examine risks from implicitly unpacking archives and remote dependencies.
6. Verify each result using explicit `podman run ... <command>` invocations.

**Before you start:** [DEEP-DIVE.md](DEEP-DIVE.md) provides an extensive explanation of build contexts, layers, shells, cache and security. This README is a complete reproduction runbook.

## Evidence honesty

The retained [course interface screenshot](evidence/01-course-page-after-session.png) displays Lab 03 material and a **Start Lab** state after the user reported deleting the temporary lab environment. It is *not* a terminal transcript, proof that tasks executed, or proof of successful output. The following files are **reconstructed, reproducible examples based on the supplied lab instructions**, not exports captured from the former environment. Replace this note only if you rerun and save genuine output.

## Prerequisites

Linux, rootless Podman available, network access, shell and tar. On Ubuntu, install Podman with `sudo apt-get update && sudo apt-get install -y podman` if missing. Check `podman --version`. Do not disable SELinux or run privileged containers as a blanket troubleshooting step.

## Start here — create the working directory and inputs

```bash
mkdir -p ~/add_vs_copy_lab && cd ~/add_vs_copy_lab
printf '%s\n' 'This is a test file for COPY instruction' > testfile.txt
printf '%s\n' 'Version 1' > version.txt
printf '%s\n' 'simulated untrusted content' > badfile
tar -czf archive.tar.gz testfile.txt
tar -czf bad.tar.gz badfile
```

**Files required in the Podman build context:** `testfile.txt`, `version.txt`, `badfile`, `archive.tar.gz`, `bad.tar.gz` and the corresponding Dockerfiles. Copy the Dockerfiles from this folder into `~/add_vs_copy_lab`, or run the builds from a cloned copy of this folder after generating the input files there. Sample inputs and archives **are included for convenience**, and the setup commands can regenerate them. These are reconstructed educational examples, not original environment exports.

## Task 1 — COPY (plain, local file)

`Dockerfile.copy`:

```dockerfile
FROM docker.io/library/alpine:3.22
COPY testfile.txt /destination/
RUN cat /destination/testfile.txt
```

```bash
podman build -t copy-demo -f Dockerfile.copy .
podman run --rm copy-demo cat /destination/testfile.txt
```

Expected verification: `This is a test file for COPY instruction`. **`RUN cat` executes during image BUILD, not automatically when the container starts.** Merely invoking `podman run --rm copy-demo` will not print the file unless the image defines an appropriate `CMD`/`ENTRYPOINT` or you supply a runtime command.

## Task 2 — ADD of a plain file

`Dockerfile.add` uses `ADD testfile.txt /destination/`. Run:

```bash
podman build -t add-demo -f Dockerfile.add .
podman run --rm add-demo cat /destination/testfile.txt
```

Expected: the same file content as Task 1. For this ordinary local text file, `ADD` gains nothing over `COPY`.

## Task 3 — local archive extraction vs COPY

```bash
podman build -t add-extract-demo -f Dockerfile.add-extract .
podman run --rm add-extract-demo ls -la /extracted/
podman run --rm add-extract-demo cat /extracted/testfile.txt
```

Expected: `testfile.txt` exists inside `/extracted/` (not a compressed tarball), and contains the original line. To see the contrast:

```bash
podman build -t copy-archive-demo -f Dockerfile.copy-archive .
podman run --rm copy-archive-demo ls -la /archive/
```

With `COPY`, `/archive/archive.tar.gz` remains an archive. **Automatic unpacking applies to recognized local tar archives, not arbitrary ZIP files, and not generally to tar archives downloaded with `ADD` from a URL.**

## Task 4 — remote HTTPS file via ADD

```bash
podman build -t add-url-demo -f Dockerfile.add-url .
podman run --rm add-url-demo head -n 10 /remote/README.md
```

Expected: readable first lines from the upstream README. This task requires live HTTPS access; the `master` URL may change, disappear or redirect. For reproducible work, use a full immutable commit reference and verify a known SHA-256 when feasible. Never assume a remote URL is trusted just because the connection is HTTPS.

## Task 5 — compare cache invalidation

For both builds, ensure the **same base image and equivalent build flags**. `--layers` requests intermediate layer caching support in Podman/Buildah environments that expose it; actual reuse still depends on version and storage settings.

```bash
printf '%s\n' 'Version 1' > version.txt
podman build --layers -t cache-demo -f Dockerfile.cache-copy .
podman run --rm cache-demo cat /app/version.txt
printf '%s\n' 'Version 2' > version.txt
podman build --layers -t cache-demo -f Dockerfile.cache-copy .
podman run --rm cache-demo cat /app/version.txt
```

Repeat with `Dockerfile.cache-add`:

```bash
printf '%s\n' 'Version 1' > version.txt
podman build --layers -t cache-add-demo -f Dockerfile.cache-add .
printf '%s\n' 'Version 2' > version.txt
podman build --layers -t cache-add-demo -f Dockerfile.cache-add .
podman run --rm cache-add-demo cat /app/version.txt
```

Expected content for the last run in each case: `Version 2`. Observe build output to determine whether earlier steps were cached. Changing a local input should invalidate the relevant `COPY`/`ADD` layer and dependent steps. **Do not interpret identical outputs alone as proof of a cache hit/miss.**

## Task 6 — harmless archive-security simulation

```bash
podman build -t security-demo -f Dockerfile.security .
podman run --rm security-demo find /malicious -type f
```

Expected: `/malicious/badfile`. The file is harmless text, not malware. The lesson is that `ADD` automatically processes a local archive: inspect source provenance and archive contents before building. Prefer `COPY` for an archive you intend to unpack manually after validation.

## Final verification

```bash
podman images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}'
podman history add-extract-demo
podman run --rm copy-demo cat /destination/testfile.txt
podman run --rm add-demo cat /destination/testfile.txt
podman run --rm add-extract-demo cat /extracted/testfile.txt
podman run --rm cache-demo cat /app/version.txt
podman run --rm cache-add-demo cat /app/version.txt
podman run --rm security-demo find /malicious -type f
```

You should see: `copy-demo`, `add-demo`, `add-extract-demo`, `copy-archive-demo` (bonus demonstration), `add-url-demo`, `cache-demo`, `cache-add-demo`, `security-demo`. No execution claims are made here without saved verification output.

## Troubleshooting quick reference

| Symptom | Diagnose | Safer action |
| --- | --- | --- |
| Build cannot find input | Check working directory, `ls -l`, ignore rules and final `.` build context | Generate input files in current context and retry |
| `ADD` did not extract | Verify file is **local**, a recognized tar archive, not ZIP/remote compressed file | `tar -tzf archive.tar.gz`; recreate file |
| Remote fetch fails | DNS, TLS, upstream response, proxy or connectivity | Check URL reachability; pin to stable committed URL |
| `RUN cat` appears only in build logs | Build-time vs runtime confusion | `podman run --rm IMAGE cat /path/file` |
| Cache result unexpected | Layers/cache switches, input checksum, edits and timestamp | Compare build output, optionally `--no-cache` for diagnostic rebuild |
| Permission denied | Rootless Podman, user namespaces, storage permissions | Inspect exact error; don't casually use `--privileged` or `setenforce 0` |

## Cleanup (optional, scoped)

```bash
podman rmi copy-demo add-demo add-extract-demo copy-archive-demo add-url-demo cache-demo cache-add-demo security-demo
rm -f testfile.txt archive.tar.gz badfile bad.tar.gz version.txt
```

Do **not** use broad pruning or run cleanup in a folder containing unrelated project data.

## Progression

**Previous:** [Lab 02 — Efficient RUN Instructions](../lab-02-efficient-run-instructions/README.md)  
**Current:** Lab 03 — ADD vs COPY  
**Next:** Topic 2 Lab 04 (pending)

**Further learning:** Study cache mounts, multi-stage builds, `.containerignore`/`.dockerignore`, build secrets and SBOM / supply-chain integrity. All are explained in [DEEP-DIVE.md](DEEP-DIVE.md).
