# Engineering Deep Dive — Optimizing `RUN`

## Why did the first build remain large after cleanup?

Container image layers are immutable snapshots/diffs. A first `RUN apt-get update` can store the package-list files as one filesystem layer. A later `RUN rm -rf /var/lib/apt/lists/*` records *deletions* in a higher layer (whiteout markers); it does not remove the bytes already shipped in the earlier layer. This is why cleanup at the end of a **single** `RUN` instruction is beneficial: temporary lists need not be included in its final filesystem diff.

## Shell vs exec form

```dockerfile
RUN apk add --no-cache curl
RUN ["apk", "add", "--no-cache", "curl"]
RUN ["/bin/sh", "-c", "apk add --no-cache curl"]
```

The first uses a shell implicitly; the second uses the executable directly; the third uses JSON exec syntax **but intentionally launches a shell**. They are not always semantically identical once variables, pipelines, globbing or shell builtins are involved.

## What the evidence actually proves

The recorded optimized build was successfully tagged `localhost/optimized-nginx:latest`. The screenshot lists optimized `116 MB`, inefficient `160 MB`, and both Alpine examples at `14.1 MB`. It shows history output for both Ubuntu images and a three-vs-one `RUN` comparison. It does **not** show a direct `curl --version`, HTTP request to nginx, image vulnerability scan, digest lock, or a fully repeated build under controlled identical conditions.

## Limitations and improvements

- The `ubuntu:latest` and `alpine:latest` examples follow the training exercises and are not reproducibly pinned. For production, choose a maintained release/digest and periodically update deliberately.
- Image-size gains cannot be attributed only to reducing the number of `RUN` statements: which files survive each layer, selected packages, build caches and base image identity matter.
- Use `--no-install-recommends` only consistently across comparison variants if isolating layer impact.
- `apt-get` installations can display `debconf` warnings in noninteractive build environments without failing. Validate build exit status and resulting functionality.
- Do not use `podman image prune -a` indiscriminately in a shared lab environment.

## Optional follow-up commands

```bash
podman history --no-trunc optimized-nginx
podman history --no-trunc inefficient-multi-layer
podman image inspect optimized-nginx
podman image inspect inefficient-multi-layer
```

For improved production workflows: use digest-pinned base images, minimal packages, vulnerability scanning and CI image-policy checks.
