# Lab 05 — Managing Container Images

**Status:** Completed (self-reported; explicitly confirmed 18 October 2026)  
**Track:** Domain 5 → Linux and Open Source → Red Hat 1

## Purpose

Find, download, list, inspect and safely remove OCI container images using Podman.

## 1 — Search Docker Hub

```bash
podman search docker.io/ubuntu
podman search --filter=is-official=true docker.io/ubuntu
```

A search returns available image references and descriptions; it **does not download** images. Registry filters or output columns may vary by Podman version and registry.

## 2 — Pull an image and understand tags

```bash
podman pull docker.io/library/ubuntu:latest
podman pull docker.io/library/ubuntu:20.04
podman images
```

- `docker.io` = registry; `library/ubuntu` = official repository; `:20.04` = tag.
- A mutable tag such as `latest` can be changed by the registry publisher; for reproducible production deployments, use a supported version and/or pinned digest.
- Ubuntu 20.04 is retained here **only as a training example**, not a recommended production base image.

## 3 — Inspect image metadata

```bash
podman image inspect docker.io/library/ubuntu:latest
podman image inspect --format '{{.Config.Env}}' docker.io/library/ubuntu:latest
podman image inspect --format '{{.Architecture}}' docker.io/library/ubuntu:latest
```

Inspection reveals image configuration and metadata; outputs depend on the image and installed Podman version.

## 4 — Remove a particular image safely

```bash
podman rmi docker.io/library/ubuntu:20.04
podman images
```

**Do not indiscriminately execute** `podman image prune -a` on a shared or reused lab host: it may remove unrelated unused images. Similarly, avoid `podman rmi -f` unless you understand which containers/images are affected.

## Outcome

Practiced the full image management lifecycle: **search → pull → inspect → selectively remove**.

## Evidence

The learner explicitly confirmed completion of Lab 05. No screenshot or verified terminal transcript has been published for this lab.
