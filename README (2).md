# Lab 02 — Exploring Podman CLI

**Status:** Completed (self-reported)  
**Track:** Domain 5 → Linux and Open Source → Red Hat 1

## Purpose

Explore the lifecycle of containers and the Podman commands used to inspect and manage them.

## Commands and concepts

```bash
podman ps                      # Running containers
podman ps -a                   # Running + exited containers
podman inspect CONTAINER_NAME  # Detailed configuration and state
podman stop CONTAINER_NAME
podman start CONTAINER_NAME
podman restart CONTAINER_NAME
podman rm CONTAINER_NAME       # Remove a stopped container
```

For lifecycle practice, a process must remain alive:

```bash
podman run -d --name lab02-alpine docker.io/library/alpine:latest sleep 3600
podman ps
podman exec -it lab02-alpine sh
# Exit the exec shell; the sleep process remains running.
podman stop lab02-alpine
podman rm lab02-alpine
```

## Troubleshooting lesson

`podman run -it ... alpine sh` starts an interactive shell; after `exit`, that shell ends and the container typically shows as `Exited` under `podman ps -a`. **`-d` detaches the terminal but does not keep an otherwise finished process running.**

## Evidence

No separate terminal output has been attached to this repository. Completion was confirmed by the learner.
