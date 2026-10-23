# Deep Dive — Securing Container Images with Least Privilege

**An approachable engineering handbook: beginner → practitioner → interview readiness**  
**Companion lab:** [README.md](README.md)  
**Learning focus:** vulnerability scanning, layering, image minimalism, identity, runtime security, artifact integrity, cryptographic signing, and container supply chain.

> Learn to ask *what security property are we trying to prove, which control provides it, and which test shows that the control actually works?*

## Reading map

1. The threat model and the principle of least privilege
2. Container images: what they contain and how they are identified
3. Base-image selection and supply-chain trust
4. Vulnerability scanning with Trivy
5. CVEs, severity, exploitability and patch strategy
6. Layering and cache cleanup—what really makes images smaller
7. Alpine and minimal image trade-offs
8. Linux users, groups, permissions and namespaces
9. Root in an image versus root on the host
10. Running Nginx without root: decisions explained line-by-line
11. Restricted ports, PID files, temp paths and filesystem access
12. Linux capabilities, no-new-privileges, seccomp and SELinux
13. Signing, checksum, digest and trusted identity
14. Reproducibility, SBOM, provenance and CI gates
15. Debugging flow and common failures
16. Hands-on exercises, verification plan and interview questions
17. Applied engineering scenarios and final cheat sheet

---

## 1 · The threat model: what could go wrong?

Imagine a company deploys a public web application as a container. The application starts, returns HTTP 200, and the dashboard looks healthy. Are we finished? Not remotely. Consider five different failure paths:

- A dependency in the base image has a remotely exploitable vulnerability.
- A compromised application runs as container root and can overwrite unexpected files.
- The container bundles compilers, shells, package managers or other tools it never needs.
- The image came from an unexpected publisher or changed after approval.
- The Dockerfile appears minimal, but old image layers retain large amounts of packaged content.

These are different problems. No single flag or scanner addresses them all. We reduce risk by **defense in depth**.

The **principle of least privilege** means granting a process only the access needed to do its job, for only as long as it needs it. For a static Nginx response, the process does not need container root, privilege escalation, broad filesystem write access or all Linux capabilities.

### Threat ≠ vulnerability ≠ risk

- **Threat:** something that could harm the system (for example, a malicious request).
- **Vulnerability:** a weakness the threat might exploit (for example, an exploitable package bug).
- **Risk:** the likelihood and impact in the deployment context.

**Example:** A CVE in a package not used by this service is not the same as an actively exploitable bug in an internet-exposed component. Both deserve triage, but different priorities.

---

## 2 · The image mental model

A container **image** is a packaged set of filesystem changes (layers) and configuration (runtime user, environment, working directory, entrypoint/command, exposed ports, labels). At runtime, a container adds a writable layer on top of those image layers.

Think of it as:

```text
layer A  alpine base system
layer B  nginx packages and dependencies
layer C  nginx.conf
metadata USER nginxuser · EXPOSE 8080 · CMD nginx ...
--------------------------------------------------
container writable layer / process runtime state
```

The layers are content-addressed. Layer `C` does not rewrite layer `A` in place. This matters for caching, distribution and cleanup.

### `latest` is not a version guarantee

`latest` is a mutable *tag*. It can point to new manifests later. This is convenient for learning but is undesirable when building a deterministic production release. For a stable build, choose a supported version and ideally pin by digest (for example, `image@sha256:<real-manifest-digest>`). Digests must come from the actual registry; never make one up.

### Image ID versus manifest digest

`podman image inspect <image>` returns local identity metadata. The **registry manifest digest** used in `repo@sha256:...` describes a remote manifest and is not necessarily the same string as the image's local configuration ID. In particular, multi-platform images and manifests complicate the picture. Keep those terms distinct.

---

## 3 · Image source: choosing a trustworthy foundation

Before vulnerability scanning, ask who maintains the image and where it is pulled from.

A practical source-selection checklist:

- Published by an accountable organization or vendor?
- Patches published regularly? Is the operating system still supported?
- Correct CPU architecture, libc expectations and required application dependencies?
- Is a fixed version or digest available? Is signing/trust verifiable?
- Are images reproducible enough for a teammate to rebuild and audit?

Avoid adopting community images solely because they have a few megabytes shaved off. Maintenance and provenance often matter more than the headline download size.

The lab uses official Nginx and Alpine images in examples, but **official does not mean vulnerability-free**. Always evaluate the exact version at the time of deployment.

---

## 4 · How vulnerability scanning works

An image scanner unpacks or examines image packages and metadata, identifies operating-system and application dependencies, and correlates versions against security advisories and vulnerability databases. Trivy is one tool for that.

Example from the lab:

```bash
podman run --rm docker.io/aquasec/trivy:latest \
  image --severity HIGH,CRITICAL docker.io/library/nginx:latest
```

### Why `podman scan` is unreliable here

Podman provides image pulling, building, running, and inspecting; `podman scan` is **not a standard built-in subcommand** in general installations. Some environments offer integrations or plugins. A separate maintained scanner is a more portable choice.

### What CVE fields mean

| Report column | Interpretation | Engineering question |
|---|---|---|
| Vulnerability ID | CVE/advisory identifier | Does this affect the deployed package? |
| Package | Component associated with the finding | Is it needed? |
| Installed version | Version found in image | Are we behind a supported security update? |
| Fixed version | Upstream version containing a fix, if known | Can we upgrade without breaking compatibility? |
| Severity | Typically vendor-derived ranking | Is the software reachable and exposed? |

**Severity alone is not proof of exploitability.** Use advisories, known-exploited status, exposure, package function and compensating controls when triaging.

### Why reports change across dates

A scanner may return different findings for the same mutable tag because the image tag changed. Even with a fixed digest, the advisory database may gain new information. Therefore store the scan timestamp, image digest and scanner/database version in professional evidence.

### What would count as strong proof?

A complete recorded scan could include:

- exact image reference/digest,
- scanner name and version,
- report timestamp,
- list of findings (or genuinely empty report),
- remediation or risk acceptance note.

**This lab repository does not have that terminal output; it is intentionally not simulated.**

---

## 5 · Fixing findings instead of only counting them

A junior engineer may say: "Trivy found 12 issues." A stronger engineer asks: "Which of those issues matter in this build, what changed with the remediation, and what residual risk remains?"

Practical options:

1. **Update the base image** to a patched, compatible version.
2. **Rebuild** rather than relying on an old cache when fixes have been released.
3. **Remove unnecessary packages** if the app does not need them.
4. **Upgrade a particular library** with compatibility tests.
5. **Document exceptions** where no patch exists and apply mitigating controls.
6. **Rescan the final, exact image** rather than assuming the new build fixed everything.

Never delete essential package metadata blindly just to make scanning appear "clean". Hiding evidence is not hardening.

### CVSS numerical boundaries

In CVSS v3.x, High is generally 7.0–8.9 and Critical is 9.0–10.0; scanners may integrate other advisory systems or vendor severities. Review the scoring source used by the report.

---

## 6 · Dockerfile layering: why later `rm -rf` can disappoint

Consider this intentionally inefficient pattern:

```dockerfile
FROM ubuntu:24.04
RUN apt-get update
RUN apt-get install -y nginx
RUN rm -rf /var/lib/apt/lists/*
```

Three `RUN` instructions usually create three new filesystem layers. The final deletion hides files from the merged view, but the bytes previously written to the `RUN apt-get update` layer remain part of that earlier layer.

Now compare:

```dockerfile
FROM ubuntu:24.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends nginx \
 && rm -rf /var/lib/apt/lists/*
```

Because creation and deletion happen inside the **same `RUN` step**, the package-index files do not need to be committed into a completed filesystem layer from that command. The goal is reduced unnecessary content and clearer builds.

### Why the lab's `Dockerfile.clean` may not shrink anything

The base Nginx image was already published with its own layers. Adding a separate cleanup `RUN` instruction cannot rewrite its old layers. In some cases, it actually makes the resulting image a little larger due to added metadata/diff information.

This is an important professional finding: **do not trust expected image sizes without measuring them**.

### Build caching and attack surface are separate ideas

Cleaning package indexes can reduce bloat, but does not prove that packages are removed, patched or non-executable. Attack surface relates to what can be executed and reached; image footprint relates to storage and transfer. Correlated, not identical.

---

## 7 · Minimal base images: advantages and trade-offs

The course's Alpine example is:

```dockerfile
FROM docker.io/library/alpine:latest
RUN apk add --no-cache nginx
```

Why use it? Alpine is typically small and has a compact package ecosystem. `--no-cache` tells `apk` not to persist its package index cache for that invocation.

But minimal can introduce challenges:

- Alpine commonly uses **musl libc**, while many binaries expect glibc.
- Debugging tools may not be installed.
- TLS/certificate and locale behavior needs validation depending on app requirements.
- Slimmer dependencies can expose assumptions in application scripts.
- Smaller images can still include vulnerable packages.

For workloads needing only a single static binary, distroless or `scratch` images may be appropriate, but only after studying compatibility, observability, certificates and runtime diagnostics.

### Fair image comparison

Compare the **same application capability**, not only two arbitrary tags. A small Alpine image with a different Nginx version or build configuration may not be an apples-to-apples security comparison.

Record OS, architecture, Nginx version, digest and measured size for a fair experiment.

---

## 8 · Linux permissions you need to understand

Every Linux process has credentials, typically including UID and GIDs. Files have owners, groups and permission bits. Access is determined by these identities, mode bits, and potentially ACLs, Linux security modules and other controls.

Basic commands:

```bash
id
whoami
ls -ld /app
stat -c '%a %U %G %n' /app
```

Consider:

```text
drwxr-xr-x  appuser appuser  /app
```

The owner can read, write and enter the directory. Group and others can read and enter but not write. A process running under a different UID cannot simply create a file there unless another permission rule allows it.

### Build-time and runtime privileges

During image building, commands before `USER nginxuser` execute under the current build user—often container root. Once `USER nginxuser` is set, subsequent `RUN`, `CMD` and `ENTRYPOINT` execution defaults to that user (unless overridden at runtime). You often install packages first as root, then drop privileges for the application process.

### Why fixed UID?

`10001` is a predictable non-root UID for a tutorial. It is **not** a universal magic secure number. For OpenShift environments with arbitrary injected UIDs, hardcoding one UID can need additional group permissions and testing.

---

## 9 · Root inside container versus root on host

Three notions are easily confused:

**1. Container root (`UID 0` inside namespace).** May have more authority within the container's namespace and its accessible mounts than a non-root application user.

**2. Rootless Podman.** The engine is launched by an unprivileged host account and uses user namespaces to map container IDs to host IDs. It reduces some host-level privilege requirements but is not a blanket guarantee.

**3. Privileged containers.** `--privileged` greatly expands access/capabilities and relaxes isolation. It is **not** the right solution when an app simply needs temp file permissions fixed.

Never describe a non-root container as impossible to escape. Host kernel vulnerabilities, runtime bugs, writable host mounts, exposed credentials, and excessive capabilities still matter.

---

## 10 · Non-root Nginx, line by line

See [`Dockerfile.nonroot`](Dockerfile.nonroot):

```dockerfile
FROM docker.io/library/alpine:latest
RUN apk add --no-cache nginx \
    && adduser -D -u 10001 nginxuser \
    && mkdir -p /var/lib/nginx /app \
    && chown -R nginxuser:nginxuser /var/lib/nginx /app
COPY nginx.conf /etc/nginx/nginx.conf
USER nginxuser
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
```

**FROM:** sets the base operating-system environment. Using `latest` matches the supplied class exercise, but production builds should pin a verified digest.

**RUN apk:** installs Nginx. Package installation occurs at build time with the required permissions.

**adduser -D -u 10001:** creates a non-root account with explicit UID. This account is local to the container image; it is not a newly added administrator on the host.

**mkdir and chown:** prepares expected application paths; extra broad `chmod 777` is not necessary. You should scope writable access as narrowly as practical.

**COPY:** replaces the default Nginx config with the one accompanying this repo.

**USER:** instructs the runtime to start the application as `nginxuser` by default.

**EXPOSE 8080:** image metadata describing the intended service port. It does **not** publish a host port automatically.

**CMD:** launches Nginx in the foreground so the container lifecycle tracks the service.

### Why the config must match

A copied Nginx file must be internally correct. The companion [`nginx.conf`](nginx.conf) defines `events` and `http` blocks, listens on port `8080`, writes logs to standard streams, places its PID in `/tmp`, and uses writable temp paths.

Do not keep the course's original `USER nginxuser` example plus a standard root-oriented Nginx config and assume it will run successfully.

---

## 11 · Ports, filesystem paths and app startup

### Low-numbered ports

On traditional Linux setups, binding ports below `1024` requires special privilege; exact container behavior varies with sysctl settings and namespace/runtime configuration. Port `8080` avoids this complication for an ordinary user.

The published port mapping `-p 8080:8080` means:

- host interface listens at port `8080`,
- forwarded traffic reaches port `8080` inside the container.

If you use `-p 8080:80` while your configuration listens on `8080` internally, the mapping will be wrong.

### Writable PID path

Nginx needs to record its process ID. `/run` or `/var/run` may not be writable for the non-root user in a minimal image. Use `pid /tmp/nginx.pid;` for this controlled lab.

### Temporary request paths

Reverse-proxy features, body buffering and upstream integrations may require temp files. The lab places Nginx's various temp paths beneath `/tmp` rather than a privileged system directory.

### Logs and container observability

Using `/dev/stdout` and `/dev/stderr` lets `podman logs secure_nginx` display log messages and prevents the process from requiring a writable log folder under `/var/log`.

---

## 12 · Add more protections: capabilities and no-new-privileges

The lab starts the process with:

```bash
podman run -d --name secure_nginx \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  -p 8080:8080 nginx_nonroot
```

### Linux capabilities

Root capabilities divide broad root privilege into narrower authorities (such as changing network configuration or overriding file permissions). `--cap-drop=ALL` drops the container's default capabilities, which is suitable for this simple HTTP server if nothing requires them. Not all services can operate with every capability dropped; test and add back only a clearly needed one.

### No new privileges

`no-new-privileges` prevents certain privilege gains through exec-related privilege transitions. It complements, rather than replaces, running as non-root.

### Keep the runtime safe by default

Possible future controls: readonly root filesystem plus specific writable tmpfs mounts, resource limits, network restrictions, reduced syscalls via seccomp, SELinux/AppArmor confinement, and dropping unneeded mounts. Each requires compatibility testing.

### SELinux volume mounts

On systems using SELinux, bind-mounted content can have labels preventing container access. Podman's `:Z`/`:z` volume options are relevant, but do not disable SELinux globally merely to make a demo pass.

---

## 13 · Images: provenance and integrity are different from security scanning

**Provenance:** who built this artifact, from which source and inputs, under what process?  
**Integrity:** do the bytes match a known reference?  
**Vulnerability scanning:** does this artifact contain components with known advisories?  
**Runtime hardening:** what can the deployed process actually do?

These four questions need separate evidence and controls.

### Hash a locally saved archive

```bash
podman save --format oci-archive -o nginx_nonroot.oci.tar nginx_nonroot
sha256sum nginx_nonroot.oci.tar
```

The output is a fingerprint of the **exported archive bytes**. If the archive changes, its SHA-256 usually changes. But if an attacker can replace both the archive and its hash file, an unsigned reference hash is not sufficient for authentication.

### Sign the archive with GPG

If you already own a signing key:

```bash
gpg --armor --detach-sign --output nginx_nonroot.oci.tar.asc nginx_nonroot.oci.tar
gpg --verify nginx_nonroot.oci.tar.asc nginx_nonroot.oci.tar
```

Verification is meaningful only if the public signing key is itself authenticated by a trusted channel. A successful local signature check does **not** assert that the image was signed in a registry or that the signer followed a secure build process.

### `podman image sign`

Podman's built-in signing workflow refers to images pulled/published with registry transports and can store signatures according to configured `registries.d` signstores. It requires a suitable signing identity and key configuration. A bare local image tag and arbitrary email address are not a complete signing recipe.

### `podman image trust show`

This command lists registry trust policies; it **does not list the signatures on all local images**. Trust policies can require signatures for a particular registry/repository scope, but enforcing and verifying that policy requires correct configuration and a real pull/verification workflow.

---

## 14 · SBOM, signing, attestation and CI/CD

An **SBOM** (Software Bill of Materials) describes included components, often in formats such as SPDX or CycloneDX. It provides visibility that complements scanning but is not a safety guarantee.

A stronger deployment workflow might look like:

```text
Source commit
    |
    v
Build with pinned base digest
    |
    +--> generate SBOM / provenance metadata
    |
    v
Scan final container image for vulnerabilities
    |
    v
Run tests and least-privilege checks
    |
    v
Sign immutable image digest with a controlled identity
    |
    v
Push to registry
    |
    v
Verify signature + policy before deployment
    |
    v
Observe service and periodically rescan
```

**Exercise versus implementation:** This is the target pattern for a professional DevSecOps pipeline, not something this specific training repository claims to have fully executed.

### Why digests beat mutable tags in approvals

If your approval checks `nginx_nonroot:latest` but the tag moves to a different image between approval and deployment, your scan and deployed bytes can diverge. Approve and deploy a specific digest to reduce this category of mismatch.

### What should a security gate do?

A gate can fail a build on material vulnerabilities or configuration errors, but must account for scanner accuracy, remediation time and explicit risk exceptions. A noisy gate that developers work around does not improve security.

---

## 15 · Troubleshooting decision tree

### Problem A: `podman scan` command not recognized

**Cause:** Standard Podman does not provide that subcommand.  
**Response:** Use Trivy, Grype or another supported scanner, and document which tool/version was used.

### Problem B: Trivy reports image not found

**Cause:** It may be looking in a local container daemon or the wrong registry.  
**Response:** Scan a fully qualified registry name, start/configure Podman socket if using direct local scanning, or export a compatible image archive and use `trivy image --input`.

### Problem C: image size didn't shrink after `rm -rf`

**Cause:** Deleted bytes still exist in older image layers.  
**Response:** Combine installation/cleanup within the same `RUN` instruction when building the layer, or choose a more minimal base.

### Problem D: Nginx exits on startup

**Investigate:**

```bash
podman ps -a
podman logs secure_nginx
```

Look for `permission denied`, inability to create a PID file, inability to bind a port, wrong config path, or missing temp directory. Fix those locations and rebuild. Do **not** jump to `--privileged`.

### Problem E: HTTP request times out

**Checklist:** running container, port mapping, Nginx listening address, host firewall, upstream access restrictions.  
**Commands:**

```bash
podman port secure_nginx
podman logs secure_nginx
curl -v http://127.0.0.1:8080
```

### Problem F: `gpg --verify` fails

**Check:** correct paired archive/signature, unchanged archive, installed public key, and verification against a trusted key identity. A bad signature is not resolved by disabling signature checks.

### Problem G: image trust policy doesn't list signed image

**Cause:** It was never supposed to; it displays policy requirements, not a per-image signature inventory.  
**Response:** Use an actual registry signing and pull-verification workflow appropriate to your environment.

---

## 16 · How to prove the lab if you ever rerun it

Do not spend time manufacturing output. A concise evidence collection should capture only high-value observations:

| Screenshot | Real output to capture | Claim supported |
|---|---|---|
| Scan report | Trivy CVE table + scanned image reference | Vulnerability review conducted |
| Image comparison | `podman images` and `podman history` | Actual image sizes and layer behavior |
| Non-root runtime | `podman exec ... id`, `podman top`, `curl` | User identity + service response |
| Optional provenance | Successful signature verification and trusted key identity | Precisely the signed artifact is verified |

If time is scarce, save command output with `tee` rather than taking many screenshots. However, **this archive contains none of these execution logs**. The included course screenshot is only a reference to the training lab material.

---

## 17 · Real-world scenario: a vulnerable web gateway

A small team runs Nginx as a reverse proxy. A scanner reports a HIGH severity issue in a library used by the image. The old process runs as root, and the container filesystem is broadly writable.

A useful improvement sequence:

1. Find out which **exact image digest** is deployed and whether the reported library is used.
2. Check vendor advisories and upgrade to a tested, patched build if available.
3. Keep only runtime dependencies; separate build dependencies from production runtime image.
4. Ensure the process can serve HTTP as a non-root account and remove unnecessary capabilities.
5. Scan the new image and verify the actual behavior, not only its size.
6. Sign the approved image digest using a controlled identity and enforce verification at the deploy boundary.
7. Document residual risk, monitoring and rollback options.

This is an engineering process, not just a handful of Dockerfile directives.

---

## 18 · Common misconceptions

**"Alpine has fewer megabytes, so it is completely secure."** False. Smaller distribution does not make CVEs impossible.

**"I removed apt cache, so all package vulnerabilities disappeared."** False. Vulnerable binaries remain unless removed/updated.

**"`USER` is enough; no other permission controls needed."** False. File mounts, capabilities, network access and runtime isolation still matter.

**"Rootless Podman makes host breakout impossible."** False. It reduces some attack paths but not all.

**"A hash proves who built the image."** False. A bare hash identifies bytes, not authorship.

**"A signed image is guaranteed vulnerability-free."** False. Signatures show claims about identity/integrity, not code safety.

**"`podman image trust show` verified my image signature."** False. It displayed policy configuration.

**"A screenshot of the lab page proves all commands worked."** False. It proves only which course material was displayed.

---

## 19 · Interview practice with answers

### Q1. What is least privilege?
Grant a process only the permissions it needs. For a simple Nginx service, use a non-root UID, correct writable paths and minimal capabilities.

### Q2. Why is running as root risky in a container?
A compromised app may gain broader access to files, mounted resources and privileged operations, depending on runtime isolation. Non-root reduces this exposure but does not eliminate all risk.

### Q3. Why does `USER nginxuser` break stock Nginx sometimes?
The default Nginx config may assume root-owned PID/temp paths or a lower-numbered listening port. Adjust both configuration and filesystem access.

### Q4. Why use port 8080?
It is conventionally an unprivileged HTTP port, avoiding several privileged binding complications; host port mapping still must match.

### Q5. What is a CVE?
A public vulnerability identifier. Its existence alone does not prove exploitability in a specific workload.

### Q6. How would you prioritize scanner findings?
Consider severity, availability of fixes, runtime exposure, exploitability, dependency reachability and business impact. Record mitigation for accepted risk.

### Q7. Why can `RUN rm -rf /var/lib/apt/lists/*` fail to shrink an image?
If package indexes are in a previous committed layer, a later deletion creates a new filesystem change but retains lower-layer bytes in distribution.

### Q8. Why is Alpine smaller and when might it be unsuitable?
It uses a minimal design and packages, but compatibility with musl versus glibc and availability of diagnostics may be important.

### Q9. What does `EXPOSE 8080` do?
Declares intended container port metadata; it does not publish the service onto a host by itself.

### Q10. What is the difference between `podman images` and `podman history`?
The first lists images and aggregate sizes; the second helps explain the instructions/layers that contributed to the image.

### Q11. What does `--cap-drop=ALL` achieve?
Drops granted Linux capabilities in the container, limiting privilege-requiring operations; services need compatibility testing.

### Q12. What does `no-new-privileges` do?
Prevents processes from acquiring additional privileges through certain exec transitions, an extra layer alongside non-root execution.

### Q13. What is a digest?
A cryptographic content identifier (such as a registry manifest digest) used to refer to exact image bytes/metadata.

### Q14. What is the difference between hashing and signing?
Hashing gives a fingerprint; a signature enables verification against a signing identity/key, provided that key is trusted.

### Q15. Why isn't `podman image trust show` proof of a signed image?
It displays registry trust-policy rules rather than checking a particular artifact's signature.

### Q16. Why scan after a build rather than only before?
Your build can install more packages or app dependencies, changing the contents and vulnerability surface of the final artifact.

### Q17. Is vulnerability scanning a complete security test?
No. It can detect many known issues, but may miss zero-days, logic flaws, credential leakage, runtime misconfiguration and deployment mistakes.

### Q18. How would you make an image reproducible?
Pin dependencies/base digests, use versioned source and build inputs, preserve build metadata and test that builds produce expected artifacts.

### Q19. Why should secrets not be baked into images?
Image layers and registries can preserve them and distribute them to anyone with pull access; use runtime secret management instead.

### Q20. How would you show verified proof of least privilege?
Inspect runtime UID, run a relevant negative filesystem-permission test, verify port/service behavior, and capture command output with source image metadata.

---

## 20 · Practical review cheat sheet

```bash
# Identify runtime and images
podman --version
podman images
podman history nginx_nonroot

# Inspect configured image user
podman image inspect nginx_nonroot --format '{{.Config.User}}'

# Test running identity and HTTP output
podman exec secure_nginx id
podman top secure_nginx
curl -i http://127.0.0.1:8080

# Find startup errors
podman ps -a
podman logs secure_nginx

# Identify archive bytes (NOT a signature)
podman save --format oci-archive -o nginx_nonroot.oci.tar nginx_nonroot
sha256sum nginx_nonroot.oci.tar
```

### Learning outcomes you should be able to explain from memory

- Why Nginx can run as a non-root account *only after its configuration and writable paths match that decision*.
- Why deleting content in a later image layer may not reduce the downloadable size.
- Why a small base image can still contain known CVEs.
- Why image signing, scanning and runtime hardening are complementary—not interchangeable.
- What an acceptable proof screenshot would show and what the available reference screenshot does **not** show.

---

## Sources for continued learning

- [Trivy container-image scanning](https://trivy.dev/docs/latest/guide/target/container_image/)
- [Trivy `image` CLI (`--input` for archives)](https://trivy.dev/docs/dev/references/configuration/cli/trivy_image/)
- [Podman image sign](https://docs.podman.io/en/latest/markdown/podman-image-sign.1.html)
- [Podman image trust](https://docs.podman.io/en/latest/markdown/podman-image-trust.1.html)
- [Podman save](https://docs.podman.io/en/latest/markdown/podman-save.1.html)
- [NGINX Unprivileged image implementation details](https://github.com/nginx/docker-nginx-unprivileged)

**Evidence policy:** This Deep Dive is learning material, not an attestation of unrecorded lab output. Future verification should come from a fresh controlled run, with dated evidence and the exact image digest.
