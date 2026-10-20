# Lab 07 — Layer Caching and Optimization

**Domain:** 5 — Linux and Open Source · **Course:** Red Hat 1 · **Status:** Completed (self-reported) · **Date:** 2026-10-19

## Objective
Compare a baseline container image, a consolidated/cleaned image, and a multi-stage approach. Understand cache reuse, image size and layer inspection.

## Learning artifacts
This folder contains the sample Flask application, an initial Dockerfile, an optimized Dockerfile, a **corrected illustrative** multi-stage Dockerfile and a requirements file. The multi-stage example in the training handout omitted Python from the runtime stage and assumed a path that may not contain the installed packages; the included version is an alternative for reproducibility, **not a claim about the exact lab execution**.

## Reproduction
```bash
podman build -t myapp:initial -f Dockerfile.initial .
podman build -t myapp:optimized -f Dockerfile.optimized .
podman build -t myapp:multistage -f Dockerfile.multistage .
podman images
podman history myapp:optimized
podman run --rm -p 127.0.0.1:8080:8080 myapp:optimized
# Run 'curl http://localhost:8080' from another terminal.
```

**Warning:** The standalone `pip install flask` in the original Ubuntu 22.04 exercise may encounter Python packaging or repository issues depending on the image and build date. Package behavior is environment dependent. The examples here use similar instructions for the educational comparison.

## Concepts
- Each filesystem-changing build step can contribute an immutable image layer; metadata instructions do not necessarily contribute filesystem layers.
- Cache can reuse unchanged earlier steps. Changing `app.py` usually invalidates its `COPY` and following steps, not unchanged package installation steps.
- Consolidating package update/install/cleanup in one `RUN` can reduce retained package-index data.
- **Fewer layers does not automatically imply smaller images.** Base image, package contents and caches matter.
- Multi-stage builds can avoid bringing build-only tooling into the runtime image, but Python and Flask still must exist in the final runtime image.

## Evidence and limitations
Completed according to the learner's report. No original screenshots, size measurements, layer output or test logs were preserved. **No image-size reduction or speed improvement is claimed.** The included sample files are reproducibility aids, not independently verified past results.

## Helpful verification (execute to produce actual evidence)
```bash
podman images --format '{{.Repository}}:{{.Tag}} {{.Size}}'
podman history myapp:initial
podman history myapp:optimized
podman history myapp:multistage
```
Save actual output when you run these again, rather than inventing prior results.
