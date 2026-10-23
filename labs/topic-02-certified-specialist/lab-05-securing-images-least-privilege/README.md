# Lab 05 — Securing Container Images with Least Privilege

**Domain 5 → Red Hat 1 → Topic 2: Red Hat Certified Specialist in Containers**  
**Learning stack:** Linux · Podman · Nginx · Alpine · Trivy · Image integrity · Least privilege  
**Learning date:** 23 October 2026  
**Record type:** Training lab reconstruction and reusable engineering notes

> **Security is not a flag you enable once.** A container becomes safer through multiple independent controls: choosing a trustworthy base image, reducing unnecessary files, assessing vulnerabilities, running with fewer privileges, and checking image integrity.

## At a glance

| Area | What this exercise teaches | How to verify |
|---|---|---|
| Image vulnerability scanning | Find known CVEs in a chosen image | Trivy report with package/severity details |
| Package cache cleanup | Understand layers and the size limitations of later deletion | Compare `podman images` + `podman history` |
| Minimal images | Install Nginx on Alpine instead of starting from a larger distribution | Compare locally reported image sizes |
| Non-root execution | Configure Nginx to run as UID `10001`, on port `8080` | `podman exec ... id`, `podman top`, `curl` |
| Image provenance | Distinguish immutable digests, checksums, signatures, and trust policies | Image inspection and optional detached GPG verification |

### Evidence integrity — please read

The repository contains the learner's **actual screenshot of the course material page** in [`evidence/01-course-material-reference.png`](evidence/01-course-material-reference.png). **It does not show terminal output, successful vulnerability scanning, a running Nginx container, or cryptographically verified signing.** The hosted lab session was no longer available to capture those outputs. The Dockerfiles and commands below are **reconstructed reproducible examples**, not an exported copy of the original lab machine. No fabricated execution screenshot, CVE count, measured image-size reduction, or signature-verification result is presented.

---

## The engineering problem

Running a container is easy. But a reliable delivery pipeline needs to ask:

- **What packages and known vulnerabilities** are included in this image?
- **Why is this image large?** Does a later cleanup truly recover the space consumed in older layers?
- **Can the service work without root?** Which paths need write access, and which port is safe for ordinary users?
- **Can we trust the artifact?** Who produced it, which digest identifies it, and how would a signature be verified?

This lab investigates each question separately rather than treating the word *secure* as a binary outcome.

## Architecture / test flow

```text
Public base image
       |
       +--> [Task 1] Trivy vulnerability review
       |
       +--> [Task 2] Nginx image + cache cleanup
       |                 |
       +--> [Task 3] Alpine + nginx  ------> compare sizes / layers
       |                 |
       +--> [Task 4] non-root nginxuser (UID 10001)
                         |  port 8080, writable /tmp
                         +--> host localhost:8080 --> HTTP 200 test
                         |
                         +--> [Task 5] image ID / archive checksum / signing concepts
```

> **Scope:** These are local container-build exercises. They do not constitute a production security assessment or a completed signed-registry supply-chain workflow.

## Prerequisites and setup

Use a Linux system with Podman and internet connectivity. For image scanning, use **Trivy**; `podman scan nginx:latest` is **not** a standard standalone Podman subcommand. `podman image trust show` displays trust policy, not proof that an arbitrary local image is signed.

```bash
podman --version
mkdir -p ~/secure_lab
cd ~/secure_lab
```

Download the four source files from **this lab directory** into `~/secure_lab/` before executing the build steps:

- [`Dockerfile.clean`](Dockerfile.clean)
- [`Dockerfile.alpine`](Dockerfile.alpine)
- [`Dockerfile.nonroot`](Dockerfile.nonroot)
- [`nginx.conf`](nginx.conf)

Use `pwd` and `ls -l` to confirm all four files are present. Each stage has its own `-f` file, so no accidental overwriting of earlier work occurs.

---

## Task 1 — Scan an Nginx image for vulnerabilities

### Purpose

Identify known vulnerabilities in the software packages included in the container image. A CVE is a published identifier for a known vulnerability; its severity is **not by itself** a complete measure of exploitability in your deployment.

### Execute

```bash
podman pull docker.io/library/nginx:latest
# Trivy runs as a container and scans the image from the registry:
podman run --rm docker.io/aquasec/trivy:latest \
  image --severity HIGH,CRITICAL docker.io/library/nginx:latest
```

The first Trivy run may download its vulnerability databases. No fixed CVE count is expected because the upstream tag and advisory database can change over time.

### How to interpret

- **CVE** — the reported vulnerability identifier.
- **Package / installed version** — where the issue is detected.
- **Fixed version** — candidate remediation when available; verify compatibility.
- **Severity** — prioritization input; also consider reachability, exposure and whether the affected package is actually used.

**Meaningful outcome:** A real report, *including possibly zero reported findings*, is obtained and inspected. No report from this historical lab is archived here.

---

## Task 2 — Clean package-cache paths and study image layers

### Purpose

Use [`Dockerfile.clean`](Dockerfile.clean) to explore whether deleting cached files from a parent image makes a child image smaller.

```bash
podman build -f Dockerfile.clean -t nginx_clean .
podman images
podman history nginx_clean
```

**Critical nuance:** A container image is built in layers. Deleting files in a **later** layer hides them in the merged filesystem, but does not necessarily remove bytes from the already-published lower layer. **Do not promise that `nginx_clean` is smaller.** The most effective build pattern is to install dependencies and clean transient artifacts in the **same `RUN` instruction that created them**.

The Dockerfile here is deliberately a teaching example, not a recommendation to overwrite a vendor-maintained image just to run `rm -rf`.

---

## Task 3 — Compare a minimal Alpine-based Nginx image

### Purpose

Understand how the base distribution and package selection affect image size and maintenance.

```bash
podman build -f Dockerfile.alpine -t nginx_alpine .
podman images
podman history nginx_alpine
```

Alpine's `apk add --no-cache nginx` avoids persisting APK index caches during installation. Compare measured sizes on **your** computer. Do not assert a specific numerical savings without measured output. Small images can still have vulnerabilities; continue patching and scanning.

---

## Task 4 — Build and run a genuinely non-root Nginx container

### Problem to solve

Setting `USER nginxuser` alone does not automatically make a service work. Default Nginx settings may want port `80`, a PID file under a root-owned runtime directory, or temporary directories the non-root account cannot write.

### Implementation decisions

[`Dockerfile.nonroot`](Dockerfile.nonroot) and [`nginx.conf`](nginx.conf) are paired intentionally:

1. Create user `nginxuser` with fixed UID `10001`.
2. Move the listening port to unprivileged `8080`.
3. Put the PID file and request temp paths in writable `/tmp`.
4. Set `USER nginxuser`, so the master process starts without root privileges.
5. Drop Linux capabilities and prevent privilege escalation in the Podman run command.

### Execute

```bash
podman build -f Dockerfile.nonroot -t nginx_nonroot .
podman run -d --name secure_nginx \
  --cap-drop=ALL --security-opt=no-new-privileges \
  -p 8080:8080 nginx_nonroot
podman ps
podman exec secure_nginx id
podman top secure_nginx
curl -i http://localhost:8080
```

Expected **when executed successfully**:

- `podman ps` shows `secure_nginx` running.
- `id` reports `uid=10001(nginxuser)`.
- `curl` shows an HTTP response with body `Secure Nginx - Non Root Container`.

A demonstration-only negative test of restricted filesystem access:

```bash
podman run --rm nginx_nonroot sh -c 'touch /root/should-fail'
```

**Expected:** permission denied; this is a security boundary working, not a reason to run `--privileged`. Container rootlessness is **not** complete isolation and does not remove the need for host/kernel hardening.

### If the service fails

```bash
podman ps -a
podman logs secure_nginx
podman exec secure_nginx id
```

Check file permissions, PID/temp paths, port conflicts and SELinux volume labels if mounts are introduced. The image does **not** need `--privileged` to work.

---

## Task 5 — Image identity, integrity and provenance

### Understand three distinct mechanisms

| Technique | What it proves | What it does **not** prove |
|---|---|---|
| Image digest | Exact registry image bytes/manifest identity | Trusted publisher or absence of vulnerabilities |
| SHA-256 checksum | Archive bytes have not changed against a known reference hash | Authorship, unless reference hash is trusted |
| Cryptographic signature | Verification against a signing key and referenced artifact | That the code is safe or execution is hardened |

### Build an optional integrity exercise

```bash
podman image inspect nginx_nonroot --format '{{.Id}}'
podman save --format oci-archive -o nginx_nonroot.oci.tar nginx_nonroot
sha256sum nginx_nonroot.oci.tar
```

**Optional detached signature**, only if a personally controlled GPG key is already configured:

```bash
gpg --list-secret-keys
gpg --armor --detach-sign --output nginx_nonroot.oci.tar.asc nginx_nonroot.oci.tar
gpg --verify nginx_nonroot.oci.tar.asc nginx_nonroot.oci.tar
```

This signs the **local exported archive**, not a registry-hosted OCI image manifest. For Podman's *registry image signing*, `podman image sign` requires an appropriate image reference, signing identity and storage/trust configuration; `podman image trust show` displays policies rather than validating this archive. **Do not claim a completed registry image signature from the checksum step.** Never commit GPG private keys or credentials.

### After the lab

You may also scan the locally built image by saving a **Docker-compatible archive** and using Trivy's `--input` mode (once Trivy is installed):

```bash
podman save -o nginx_nonroot.tar nginx_nonroot
trivy image --input nginx_nonroot.tar --severity HIGH,CRITICAL
```

The `trivy` executable must be installed on the host for the last command; alternatively run the Trivy container with an appropriate read-only bind mount.

---

## Verification matrix

| Claim | Test command | Archived evidence status |
|---|---|---|
| Known CVEs reviewed | `trivy image ...` | Not captured |
| Cache layer effect studied | `podman history nginx_clean` | Not captured |
| Alpine comparison completed | `podman images` | Not captured |
| Non-root identity verified | `podman exec secure_nginx id` | Not captured |
| HTTP response obtained | `curl -i http://localhost:8080` | Not captured |
| Cryptographic registry signature verified | Dedicated registry signing/trust workflow | Not captured / not established |
| Original course material referenced | [`evidence/01-course-material-reference.png`](evidence/01-course-material-reference.png) | Available — not execution proof |

**Reported learning activity vs. independently verified results:** The learner reported working through this training lab, but terminal proof was not retained. The repository documents the reproducible implementation and identifies what still needs evidence.

## Cleanup (only after you no longer need this local lab)

```bash
podman rm -f secure_nginx 2>/dev/null || true
podman rmi nginx_clean nginx_alpine nginx_nonroot
# Optional: remove local exported archives; do NOT delete source files.
rm -f nginx_nonroot.tar nginx_nonroot.oci.tar nginx_nonroot.oci.tar.asc
```

Avoid global `podman image prune -a` if you want to keep images from other exercises.

## Key lessons — beyond the tutorial

1. **Visibility:** Scan exact versions and prioritize vulnerabilities by actual risk.
2. **Build discipline:** Optimize layers at the time files are created; an extra cleanup layer is not a magic size reduction.
3. **Minimalism:** Reduce packages and ongoing maintenance, but do not confuse minimal with invulnerable.
4. **Runtime isolation:** `USER`, filesystem ownership, least privilege, reduced capabilities and sensible ports work together.
5. **Supply-chain integrity:** A scan, a digest and a signature answer different security questions.

## Deep Dive — zero-to-advanced reference

For layered-file-system examples, threat modeling, end-to-end troubleshooting, signing versus trust, OpenShift/Kubernetes application and interview questions, read:

**[DEEP-DIVE.md — The Container Image Security Handbook](DEEP-DIVE.md)**

## Further reading

- [Trivy — scanning container images](https://trivy.dev/docs/latest/guide/target/container_image/)
- [Trivy — image CLI and archive inputs](https://trivy.dev/docs/dev/references/configuration/cli/trivy_image/)
- [Podman — image signing](https://docs.podman.io/en/latest/markdown/podman-image-sign.1.html)
- [Podman — trust policies](https://docs.podman.io/en/latest/markdown/podman-image-trust.1.html)
- [NGINX unprivileged reference](https://github.com/nginx/docker-nginx-unprivileged)

---

**Documentation principle:** practical source files + explanations + accurate evidence labels. Never substitute illustration, predicted output or generated screenshots for evidence of a completed run.
