# Lab 03 — Running Containers with Podman

**Status:** Completed (self-reported)  
**Track:** Domain 5 → Linux and Open Source → Red Hat 1

## Purpose

Run Nginx, map ports, serve custom static content through a host bind mount, and manage a named container.

## Networking

```bash
podman run -d --name lab03-nginx -p 127.0.0.1:8080:80 docker.io/library/nginx:alpine
podman ps
curl http://localhost:8080
```

- `8080` is a host-side port; `80` is the container-side port.
- `127.0.0.1` restricts the host-side listener to the machine running Podman.
- If the terminal is on a **remote lab machine**, that machine's `localhost` is not the local laptop's `localhost`.

## Host bind mount

```bash
mkdir -p "$HOME/nginx-content"
printf '%s\n' '<h1>Hello from host!</h1>' > "$HOME/nginx-content/index.html"
podman run -d --name lab03-mounted-nginx \
  -p 127.0.0.1:8081:80 \
  -v "$HOME/nginx-content:/usr/share/nginx/html:Z" \
  docker.io/library/nginx:alpine
curl http://localhost:8081
```

The `:Z` suffix is an SELinux relabeling option, useful on SELinux-enabled systems when permitted. A volume/bind mount is not the same as copying files into a custom image.

## Names and targeted cleanup

```bash
podman inspect lab03-mounted-nginx --format '{{.State.Status}}'
podman stop lab03-mounted-nginx
podman rm lab03-mounted-nginx
podman stop lab03-nginx
podman rm lab03-nginx
```

These commands are examples: do not rerun them on differently named containers without checking current names first. Avoid blanket stop/remove commands that affect all containers.

## Observations and evidence

The learner reported a successful `curl http://localhost:8081` response with the custom `Hello from host!` page and captured **two screenshots** for the whole lab. Screenshots have not been included here; link sanitized copies once reviewed.

See [evidence guide](../../evidence/README.md).
