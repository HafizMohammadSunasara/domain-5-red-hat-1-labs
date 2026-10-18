# Lab 01 — Introduction to Containers

**Status:** Completed (self-reported)  
**Track:** Domain 5 → Linux and Open Source → Red Hat 1

## Purpose

Understand what a container is, how it differs from a virtual machine and how a containerized Linux process runs through Podman.

## Concepts studied

- Containers package a process and its runtime dependencies; they use the host OS kernel rather than booting a separate guest kernel.
- OCI container images provide the filesystem/configuration used when starting a container.
- A container does not need to continue running after the entry process exits.
- Alpine provides a small Linux environment suitable for simple interactive experiments.

## Reference commands

```bash
podman --version
podman run --rm docker.io/library/hello-world
podman run --rm -it docker.io/library/alpine:latest sh
# Within Alpine: cat /etc/os-release, then exit
```

These are reusable examples of the concepts, **not copied terminal transcripts**.

## Key lesson

Image != running container. A container's status depends primarily on whether its main process remains alive.

## Evidence

No screenshot was saved for this lab. Completion was confirmed by the learner.
