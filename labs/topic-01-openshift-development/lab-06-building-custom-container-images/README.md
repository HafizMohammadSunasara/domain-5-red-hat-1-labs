# Lab 06 — Building Custom Container Images

**Domain:** 5 — Linux and Open Source · **Course:** Red Hat 1 · **Status:** Completed (self-reported) · **Date:** 2026-10-19

## Objective
Create a custom Nginx image with Podman using `FROM`, `ENV`, `COPY` and `RUN`. Distinguish image build time from container runtime.

## Reproducible files
Create a folder containing `Containerfile` and `index.html` (included alongside this README).

```bash
podman build -t my-custom-nginx:v1 .
podman images my-custom-nginx
podman run -d --name lab6-nginx -p 127.0.0.1:8083:80 my-custom-nginx:v1
curl http://localhost:8083
podman exec lab6-nginx cat /build-info.txt
```

> Commands are reproducibility instructions, **not saved execution logs**. Port 8083 is a local alternative to the source exercise's port 8080 to reduce conflicts.

## Engineering notes
- `FROM` chooses a base image.
- `ENV` defines image-level runtime defaults.
- `COPY` packages local files from the build context into the image (not a live bind mount).
- `RUN` executes at image build time; the Nginx base image supplies the default startup command.
- Editing a host `index.html` after an image build does not update already-running containers: rebuild and deploy a new container.

## Verification procedure
Check that the image exists, the container is running, the HTTP response contains the custom heading, and `/build-info.txt` contains the build message.

## Evidence and limitations
The learner confirmed completing the lab. No original terminal output, screenshot, or runtime logs were retained for this exercise. This document is a technical reproduction guide, **not independent proof of original execution**. Avoid claiming a live production deployment based on this training exercise.

## Targeted cleanup
```bash
podman stop lab6-nginx
podman rm lab6-nginx
```
Only remove the image when it is no longer needed.
