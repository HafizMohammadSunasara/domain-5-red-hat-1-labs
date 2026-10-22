# Engineering Deep Dive — ADD vs COPY: from zero to confident reasoning

**Topic 2 · Lab 03 | A long-term learning reference**  
*This tutorial teaches principles, experiments, diagnostics and safer engineering habits. Reading a document alone does not confer professional experience: confidence comes from reproducing results, predicting failures and debugging unfamiliar cases.*

## 0. The mental model: what is an image build?

Picture a factory producing sealed boxes. A **Containerfile/Dockerfile** is the assembly plan; the **build context** is the box of raw materials delivered to the factory; the **base image** is the starting material; each `COPY`, `ADD` and `RUN` instruction transforms the output. The resulting **image** is a packaged artifact. A **container** is a running or stopped instance of that artifact with a writable runtime layer.

`COPY` and `ADD` happen when the image is **built**. They do not transfer live files into an already-running container. Editing `testfile.txt` after building does not magically update existing images or containers. To get a changed file into a rebuilt image, rebuild; for live development, consider a deliberately configured bind mount instead.

### A build pipeline in one picture

```text
Host working directory (= build context, often '.')
  ├── Dockerfile.copy
  └── testfile.txt ─────┐
                        │  COPY/ADD during build
Base image: Alpine ────┼────> New image filesystem ────> podman run
                        │          /destination/testfile.txt
Instructions & cache ─┘
```

**Quick recall:** `FROM` establishes a base; `COPY` transports bytes from context; `ADD` can also process recognized local tar archives or fetch remote data; `RUN` executes a command while assembling the image; `CMD` supplies a default *container runtime* command. `RUN` output is not equivalent to `podman run` output.

## 1. Anatomy of COPY

```dockerfile
FROM docker.io/library/alpine:3.22
COPY testfile.txt /destination/
RUN cat /destination/testfile.txt
```

Read it aloud: “Start with Alpine; take the file named `testfile.txt` from the build context and place it in the image under `/destination/`; while building, print its content.”

- Source: relative to the build context, **not** an arbitrary filesystem path on the host.
- Destination: a path **inside** the built image, not the host's `/destination`.
- Trailing slash: `/destination/` clearly represents a directory; the build tool creates it as needed.
- If source is absent/ignored, build should fail. Verify location using `pwd`, `ls -la`, ignore files and the final dot in `podman build ... .`.
- Simple `COPY` doesn't unpack archives or HTTP-fetch arbitrary URLs.

**Prediction exercise:** What happens if `testfile.txt` contains two lines? Both lines will be copied as bytes and printed by `cat`. What if it is edited later? The already-built image retains the old contents until rebuilt.

### Files, directories, patterns and permissions

`COPY app/ /app/` copies the **contents** of the `app` directory into `/app/` as specified by the build engine's file-copy semantics. Treat glob patterns carefully and test your actual tool version. Metadata such as mode and ownership affect runtime behavior; many builders support `COPY --chown=...` and `--chmod=...` but support/details may vary. Don't assume that copying a source file also makes it executable.

To diagnose:

```bash
podman run --rm copy-demo ls -l /destination/
podman run --rm copy-demo cat /destination/testfile.txt
podman history copy-demo
```

## 2. Anatomy of ADD: three distinct cases

### A. Local ordinary file: same result as COPY

`ADD testfile.txt /destination/` transfers this ordinary local file, giving the same result as COPY for the lab. Prefer `COPY` because it states intent precisely and reduces hidden behavior.

### B. Local recognized tar archive: auto-extract

`ADD archive.tar.gz /extracted/` may *unpack* a recognized local tar archive into `/extracted/`. To create one:

```bash
tar -czf archive.tar.gz testfile.txt
tar -tzf archive.tar.gz
```

The `-t` listing should show `testfile.txt` before image build. After building, `/extracted/testfile.txt` exists. Contrast:

```dockerfile
COPY archive.tar.gz /archive/archive.tar.gz
```

Now you have `/archive/archive.tar.gz` in the image; **it is not extracted**. An `ADD` instruction is not a universal decompressor: ZIP files are not the same as recognized tar archives. Behavior is determined by archive content and engine support, not merely a pleasing filename extension. Validate with `tar -tzf` and the exact builder used.

### C. Remote URL: download, not implicit local-tar extraction

`ADD https://raw.githubusercontent.com/moby/moby/master/README.md /remote/README.md` requests a remote file during the build. The image will contain the fetched bytes if the build succeeds. The **source is mutable** because the `master` branch can change. HTTP success and TLS encryption don't guarantee trustworthiness or reproducibility. In a production workflow, pin a commit/immutable artifact and independently validate a cryptographic checksum or signature.

**Critical distinction:** Auto-extraction is associated with **local tar sources**. A tar downloaded over HTTPS via `ADD` is generally saved as a downloaded file, not automatically unpacked. Don't generalize Task 3 to Task 4.

## 3. Why `podman run --rm demo` can look like it 'did nothing'

Consider:

```dockerfile
FROM alpine:3.22
COPY testfile.txt /destination/
RUN cat /destination/testfile.txt
```

`RUN` executes during `podman build`; it does not become a startup command. When you later call `podman run --rm copy-demo`, the image inherits Alpine's default command (which does not automatically print this file). Execute explicitly:

```bash
podman run --rm copy-demo cat /destination/testfile.txt
```

Alternative for demonstration only:

```dockerfile
CMD ["cat", "/destination/testfile.txt"]
```

Now `podman run --rm copy-demo` can print the contents by default **after rebuilding**. Production containers should have an appropriate long-running process if they're meant to serve requests, rather than using a short `cat` command as a server.

## 4. Cache: think in a dependency chain

A builder can reuse prior work when it decides an instruction plus all relevant prior state and inputs are unchanged. For a sequence:

```dockerfile
FROM alpine:3.22
COPY version.txt /app/
RUN cat /app/version.txt
```

- When `version.txt` says `Version 1`, the image contains `Version 1`.
- Change source file to `Version 2` and rebuild. The source differs, so the `COPY` step and later dependent steps need new results; expect `Version 2` in the new image.
- Rebuild again without changes and inspect log for cache reuse (if caching enabled).
- Repeat with `ADD`; local file changes have broadly analogous invalidation behavior.

**What not to claim:** Seeing `Version 2` proves updated content ended up in the final image; it does **not** by itself prove which internal steps were or were not cache hits. Look at the actual build logs/history and the builder's cache settings. Cache behavior of remote URLs can be especially tricky; do not assume an upstream change is immediately detected merely because a URL stays the same.

### Order instructions with cache in mind

For a source-code app, frequently changing application files should generally be copied after less-frequently changed dependency manifests and installs. For example:

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
```

Why? Changing one app file does not necessarily force dependency installation to repeat, provided earlier inputs/layers remain valid. Version/digest pinning and dependency hashes are stronger reproducibility controls than relying on moving tags.

## 5. Layers, image sizes and secrets

Image layers are content-addressed filesystem changes. Replacing or deleting a secret in a later layer does not guarantee the original bytes disappeared from earlier layers. **Never** put API keys, SSH keys, passwords, `.env` contents or credentials into a build context or copy them into an image. Add ignore rules, use supported build-time secret mechanisms, and rotate secrets if accidental exposure occurs.

Archive extraction can introduce file ownership, permission or pathname surprises. Even if your engine mitigates path traversal, treat untrusted archives as untrusted inputs. Inspect outside the build where possible, verify contents, prefer trusted provenance and rebuild from verified sources. A harmless `badfile` only simulates this trust boundary; it is not an exploit demonstration.

**.containerignore / .dockerignore** helps exclude files from build context (exact precedence depends on Podman/Buildah and options). This improves build speed and lowers accidental secret exposure, but it is not a replacement for secret management or auditing.

## 6. The six tasks as scientific experiments

For each task, keep the same discipline:

| Task | Hypothesis | Intervention | Verification | Possible confounder |
| --- | --- | --- | --- | --- |
| 1 — COPY | Local text transfers unchanged | `COPY testfile.txt` | `cat` from container | Missing build-context file |
| 2 — ADD | Plain file same bytes as COPY | `ADD testfile.txt` | Same `cat` output | Source file edited between builds |
| 3 — archive | Local `.tar.gz` gets unpacked | `ADD archive.tar.gz` | `ls`, `cat`; contrast `COPY` | Invalid archive; ZIP mistaken for tar |
| 4 — URL | Image contains remote README | `ADD https://...` | `head`/`sha256sum` | Unreachable/mutable upstream |
| 5 — cache | File change alters built content | `Version 1` → `Version 2` | Both content and build log | Cache disabled, different tags |
| 6 — security | Local archive gets processed | Harmless `bad.tar.gz` | `find /malicious` | Mistaking simulation for real exploit |

A serious engineer distinguishes **prediction**, **observation**, and **interpretation**. If a build unexpectedly succeeds, do not simply say “done”: explain why, what else might be happening, and how you would falsify your hypothesis.

## 7. Frequent mistakes: symptoms → cause → fix

**`COPY failed: no source files`**  
Cause: missing file, wrong working directory, ignored file or wrong build context. Fix: `pwd; ls -l; ls -la; podman build -f Dockerfile.copy .` from the directory containing inputs. Remember `.`.

**File exists during build, but `podman run` prints nothing**  
Cause: `RUN` != `CMD`. Fix: `podman run --rm copy-demo cat /destination/testfile.txt`.

**ADD archive doesn't extract**  
Cause: archive is remote, not tar, corrupted, or not actually recognized by builder. Fix: `file archive.tar.gz` (if installed), `tar -tzf archive.tar.gz`, inspect actual source and resulting image.

**ADD URL fails**  
Cause: DNS, proxy, TLS, endpoint changed, network outage. Fix: verify network and URL, inspect precise build error; do not disable TLS verification as an expedient fix.

**Cache results confusing**  
Cause: ignored files, caching disabled, mutable base tags, or comparing non-identical builds. Fix: print source hash and final hash, record build command/log, compare identical baselines; `--no-cache` is a diagnostic control, not a permanent 'optimization'.

**Permission denied / user namespace warnings**  
Cause: environment setup, unprivileged user namespace restrictions, storage driver or SELinux labels. Fix: investigate `podman info`, `podman unshare`, storage and permission configuration. Do not reflexively run with `--privileged` and never disable SELinux globally just to make a lab pass.

## 8. Professional practices beyond the lab

1. **Reproducibility** — use explicit version tags; digest pin when you truly need immutable image identity. Record the tested builder version and architecture.
2. **Source trust** — download from vetted upstreams, pinned immutable commits/artifact versions; validate checksums/signatures when possible.
3. **Keep the context small** — do not send `.git`, credentials, giant generated files into a build by default.
4. **Least privilege** — build rootless where possible; avoid unnecessary privilege and network exposure.
5. **Keep provenance** — store Dockerfiles, inputs or generators, commands and actual outputs. Link screenshots honestly.
6. **Use explicit verification** — `podman run --rm IMAGE COMMAND`, `podman inspect`, checksums, and content assertions.
7. **Handle failures scientifically** — capture failing command, stderr, image/tool versions and hypotheses before changing multiple variables at once.
8. **Don't confuse layers and runtime mounts** — build-time files are baked into immutable image content; volumes/bind mounts have different lifecycle semantics.
9. **Don't mistake demos for production guidance** — an intentionally floating URL makes a great classroom example and a poor critical dependency.
10. **Review dependencies** — automate security scanning/SBOM generation where available, and rebuild against patched bases.

## 9. Self-check questions (with answers)

**Q1. Why is COPY normally preferable to ADD?**  
Because it expresses the simple, deterministic intent of local file copying without archive-unpacking or remote-fetch behavior.

**Q2. When is ADD useful?**  
When you intentionally want automatic extraction of a local recognized tar archive or a remote URL download and you understand the consequences.

**Q3. Does ADD extract a remote tar.gz URL automatically?**  
Generally no; remote download and local archive extraction are distinct behaviors.

**Q4. Does RUN define what a container does when started?**  
No. `RUN` happens at build time; `CMD`/`ENTRYPOINT` and supplied `podman run` arguments determine startup behavior.

**Q5. Why does Version 1 become Version 2 after rebuilding?**  
The source file changed, so a new image build incorporates new source bytes. Check build logs to make precise cache claims.

**Q6. Is fewer layers always a smaller image?**  
No. Size also depends on bytes introduced/removed in each layer, compression, base image, cache and package choices.

**Q7. Can I delete a secret in a later RUN layer and call the image safe?**  
No. Earlier layers/history may still retain it; don't put secrets in layers in the first place.

**Q8. Does an LMS page screenshot prove all terminal commands were run?**  
No. Execution evidence requires preserved logs/screenshots of the actual commands/results; state self-reported completion clearly when those are missing.

**Q9. Why shouldn't I use `sudo setenforce 0` when builds fail?**  
It weakens system security without identifying the cause, and does not even apply on many Ubuntu hosts using AppArmor.

**Q10. What would you test in a job interview?**  
Predict behavior before running a build, demonstrate COPY vs ADD, show archive/remote edge cases, explain cache invalidation and build context, and document the security implications without exaggeration.

## 10. Practice challenges to build confidence

- **Beginner:** Create two images using COPY and ADD for a two-line file. Prove their bytes match with `sha256sum` inside containers.
- **Intermediate:** Construct a tar archive with two subdirectories, show exactly where extraction puts each file, and compare with COPY of the archive itself.
- **Intermediate:** Repeat Version 1 → Version 2 with build logs saved to files. Annotate which instructions were reused, if any.
- **Advanced:** Pin a downloaded artifact to an immutable release and verify its SHA-256 before consuming it. Explain what HTTPS protects and what it does not.
- **Advanced:** Add intentional ignore rules and demonstrate that a sensitive-looking dummy `.env` cannot be copied because it is absent from the context. Never experiment with actual credentials.
- **Challenge:** Design a minimal application image with a multi-stage build; explain what data crosses stages, which layers remain, and how to create a reproducible SBOM.

## 11. Suggested demonstration evidence for a future rerun

The original temporary environment was deleted. On a later rerun, capture: (1) `podman build` + `podman run ... cat` for COPY/ADD; (2) local tar extraction vs plain COPY + remote URL; (3) Version 1/2 rebuild logs + harmless archive listing; (4) final `podman images`. Redact tokens, private hosts, secrets and personal information before sharing.

## Reference terms

**Build context:** files available to a build command; **base image:** image named in FROM; **layer:** reusable image filesystem change; **cache invalidation:** need to rebuild dependent steps after relevant inputs change; **provenance:** verifiable origin/build history; **digest:** content-based image reference; **immutable pin:** reference intended not to change; **supply chain:** systems and dependencies through which an artifact was produced.

---

**Remember:** The goal is not memorizing “ADD extracts, COPY doesn't”. The goal is choosing the **least surprising, most reproducible, least privileged** instruction for a real problem—and proving the result with evidence.
