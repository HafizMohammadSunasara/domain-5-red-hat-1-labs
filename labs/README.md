# Lab 02 — Using `RUN` Instruction Efficiently

**Skill Domain 5 → Linux and Open Source → Red Hat 1 → Topic 2: Red Hat Certified Specialist in Containers**  
**Date:** 22 October 2026  
**Status:** Completed (learner-reported); build and layer comparison supported by retained screenshots  
**Environment:** Browser-based Ubuntu training instance, Podman  
**Maintainer:** Hafiz Mohammad Sunasara

## Goal

Learn the difference between shell and exec `RUN` forms, observe how separating package installation and cleanup creates additional image layers, and verify image sizes and build histories with Podman.

## Key concepts

- `RUN command arg` (shell form) invokes the image's configured shell, normally `/bin/sh -c` on Linux.
- `RUN ["executable", "arg1", ...]` (exec form) executes without an implicit shell. `RUN ["/bin/sh", "-c", "..."]` is also exec form but explicitly invokes a shell.
- Each image-building `RUN` commonly commits filesystem changes to a new layer. Deleting files in a **later** layer does not remove the bytes already stored in an earlier layer.
- Fewer layers **do not guarantee** a smaller or faster image. The location of cache cleanup, package-selection flags, base images, and reuse of existing layers also matter.
- `latest` is a mutable tag. These educational examples follow the lab environment; production recipes should use intentionally selected version tags, ideally digests, and maintained base images.

## Repository contents

| File | Purpose |
| --- | --- |
| [`Dockerfile.shell`](Dockerfile.shell) | Alpine curl installation using shell form |
| [`Dockerfile.exec`](Dockerfile.exec) | Same install using direct exec form |
| [`Dockerfile.inefficient`](Dockerfile.inefficient) | Three separate Ubuntu `RUN` instructions |
| [`Dockerfile.optimized`](Dockerfile.optimized) | Apt update/install/cache cleanup in one `RUN` |
| [`DEEP-DIVE.md`](DEEP-DIVE.md) | Layer reasoning, caveats and troubleshooting |
| [`evidence/`](evidence/) | Three screenshots from the actual lab session |

**Provenance note:** The Dockerfiles in this repository are **reconstructed reproducible examples from the lab instructions and visible command histories**; screenshots do not establish exact byte-for-byte contents of the original files. If original Dockerfiles are later exported, replace these examples with them.

## Reproduce

Run from this directory on a machine with Podman and internet access:

```bash
podman build -f Dockerfile.shell -t run-lab-shell .
podman build -f Dockerfile.exec -t run-lab-exec .
podman run --rm run-lab-shell curl --version
podman run --rm run-lab-exec curl --version

podman build -f Dockerfile.inefficient -t inefficient-multi-layer .
podman build -f Dockerfile.optimized -t optimized-nginx .
podman images
podman history inefficient-multi-layer
podman history optimized-nginx
podman run --rm optimized-nginx nginx -v
```

> The `curl --version` and `nginx -v` checks are reproducibility instructions, **not claimed to be shown by the supplied screenshots**.

## Recorded observations

Values below are **reported by `podman images` in the uploaded lab screenshot** (displayed/rounded units, not independently measured byte counts):

| Image | Reported size | Build-history finding |
| --- | ---: | --- |
| `localhost/run-lab-shell:latest` | 14.1 MB | Image present; shell-form Dockerfile covered in exercise |
| `localhost/run-lab-exec:latest` | 14.1 MB | Image present; exec-form Dockerfile covered in exercise |
| `localhost/inefficient-multi-layer:latest` | 160 MB | Separate update, install and cleanup steps (three `RUN` instructions) |
| `localhost/optimized-nginx:latest` | 116 MB | Single combined update/install/cleanup `RUN` |

**Observed difference:** 160 − 116 = **44 MB**, approximately **27.5%** less than the inefficient image's reported size. Both recorded Ubuntu builds used `ubuntu:latest` in their image history, with the base reported as 113 MB at that time. Since the tag is mutable, future results can differ.

The inefficient image history shows an approximately **43.6 MB** `apt-get update` layer and a later deletion/cleanup layer of **18.9 kB**; that later deletion does not reclaim the content embedded in the earlier layer. The optimized image history displays a single added `RUN` layer (~**3.34 MB**). Sizes are image-history display values and need not add perfectly to rounded image totals.

## Screenshots — actual retained evidence

### Build and image size comparison

![Successful optimized build and four image sizes](evidence/01-build-and-image-sizes.png)

### Optimized image history

![One combined RUN step in optimized image history](evidence/02-optimized-image-history.png)

### Inefficient image history

![Three separate RUN steps in inefficient image history](evidence/03-inefficient-image-history.png)

## Takeaways

1. Choose shell form when shell features (`&&`, pipes, expansion) are intentional.
2. Choose exec form when you want explicit arguments without implicit shell interpretation.
3. Keep `apt-get update`, installation and `/var/lib/apt/lists` cleanup together in the same build layer.
4. Compare **actual history and image sizes**, not just instruction counts.
5. Avoid `--privileged` as a generic fix for build errors; diagnose permissions and the execution environment first.

**Next:** Continue Topic 2 with Lab 03. Do not mark additional labs completed until their executions are verified.
