# Lab 01 — Understanding the FROM Instruction

**Track:** Domain 5 → Red Hat 1 → Topic 2: Red Hat Certified Specialist in Containers  
**Date:** 22 October 2026  
**Status:** Completed — build and runtime output shown in retained screenshots  
**Environment:** Ubuntu lab terminal, Podman, Red Hat UBI 8.7

## Objective

Understand how `FROM` selects a container image's starting point, inspect a base image, pin a version tag, write a `Containerfile`, build an image, and validate its runtime filesystem.

## Why `FROM` matters

`FROM` establishes the base stage of a Containerfile. It determines the starting image, including its userspace and image metadata. Selecting a base image means balancing provenance, maintenance, application compatibility, image size, and patching requirements.

**Version tag vs digest:** `ubi:8.7` selects a specific release tag but tags can potentially be moved or replaced. Pinning a full `@sha256:...` digest is stronger for byte-for-byte build-input reproducibility. This exercise uses the course's **version tag**, not a digest.

## Reproduce

### 1. Check tools and inspect the base

```bash
podman --version
skopeo --version
podman search registry.access.redhat.com/ubi8
skopeo inspect docker://registry.access.redhat.com/ubi8/ubi:latest
podman pull registry.access.redhat.com/ubi8/ubi:8.7
```

If Skopeo is missing on Ubuntu:

```bash
sudo apt update
sudo apt install -y skopeo
```

### 2. Create the Containerfile

Run in a dedicated directory such as `~/from-lab` and use the adjacent [`Containerfile`](Containerfile). The recorded image build used:

```dockerfile
FROM registry.access.redhat.com/ubi8/ubi:8.7
LABEL maintainer="hafiz mohammad"
RUN echo "base image successfully set up" > /tmp/status.txt
```

The `RUN` instruction writes a file into the image during build. The file is then readable by containers launched from that image.

### 3. Build and verify

```bash
podman build -t my-base-image .
podman images
podman run --rm my-base-image:latest cat /tmp/status.txt
```

**Observed verification output:**

```text
base image successfully set up
```

`--rm` deletes the temporary container after it exits; it does **not** delete the image.

Optional inspection:

```bash
podman history my-base-image
```

## Evidence

| Proof | Screenshot | What it demonstrates |
| --- | --- | --- |
| Image build | [01-container-build.png](evidence/01-container-build.png) | Three build steps including `FROM`, `LABEL`, and `RUN`; warnings while building |
| Final validation | [02-image-validation.png](evidence/02-image-validation.png) | Successful image tagging, `podman images`, and output read from `/tmp/status.txt` |

![Container build terminal evidence](evidence/01-container-build.png)

![Image validation terminal evidence](evidence/02-image-validation.png)

## Observations and limitations

- The terminal showed several `can't raise ambient capability ... operation not permitted` warnings. The image nevertheless built successfully, was tagged `localhost/my-base-image:latest`, and the container read the status file. These warnings could be related to restrictions in the course lab environment; the screenshots alone do not prove their root cause.
- The screenshot shows the UBI base image with tag `8.7`, and a locally produced image with tag `latest`. The latter is the tag applied to **our own image**, not a claim that the **base** used `latest`.
- The recorded run output is lowercase, matching the actual Containerfile recorded in the terminal.
- The screenshots do not independently establish the exact `skopeo inspect` output or a digest-pinned build.

## Troubleshooting

| Symptom | Investigation |
| --- | --- |
| Image cannot be pulled | Verify the image reference/tag, network, and registry access |
| Build fails at `FROM` | Try `podman pull registry.access.redhat.com/ubi8/ubi:8.7` and inspect the precise error |
| Status file missing | Check the `RUN` line and rebuild with `podman build --no-cache -t my-base-image .` |
| Capability warnings | Verify exit status and runtime behavior; investigate environment restrictions if actual operations fail |

## What I learned

A functioning image build depends on a deliberate, traceable base image choice. A version tag is helpful but a digest is needed for stronger supply-chain pinning. A successful build should be complemented by a runtime verification—not assumed correct from build logs alone.

**Next lab:** Continue with Topic 2's next assigned exercise.
