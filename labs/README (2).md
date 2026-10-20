# Lab 08 — Environment Variables in Images

**Domain:** 5 — Linux and Open Source · **Course:** Red Hat 1 · **Status:** Completed (self-reported) · **Date:** 2026-10-19

## Objective
Define runtime defaults with `ENV`, override them with `-e` and `--env-file`, inspect container environments, and pass build-time `ARG` values.

## Task 1 — Image defaults
`Containerfile.env` contains the example using Red Hat UBI minimal and default values for `APP_NAME`, `APP_VERSION` and `APP_ENV`.

```bash
podman build -t env-demo -f Containerfile.env .
podman run env-demo
# Expected design behavior: Running MyApp v1.0 in development mode
```

## Task 2 — Override at runtime
```bash
podman run -e APP_ENV=production -e APP_VERSION=2.0 env-demo
podman run --env-file=app.env env-demo
```

Runtime overrides apply to a new container, not by rewriting the original image. `app.env` in this folder contains non-secret demonstration settings only.

## Task 3 — Inspect and build arguments
The source handout starts a detached container and then runs `podman exec`, but `env-demo` executes only `echo` and exits immediately. `-d` does **not** keep its main process alive. A direct check works without keeping a container running:

```bash
podman run --rm --entrypoint env env-demo
podman build --build-arg APP_BUILD_NUMBER=42 -t arg-demo -f Containerfile.arg .
podman run arg-demo
# Expected design behavior: Build number: 42
```

`ARG` is build-scoped; this sample copies its value into `ENV APP_BUILD` so it remains available when the container runs. Never place secrets in `ARG` or `ENV` because they can be disclosed in image history/metadata.

## Evidence and limitations
The learner reports completing all tasks; no original screenshots or terminal transcripts are attached. Examples and expected behaviors are **not represented as saved lab results**. These files make the exercise reproducible.

## Cleanup safety
Avoid `podman rm -f $(podman ps -aq)`: it would delete unrelated containers. Inspect lab-specific resources and remove only those you own.
