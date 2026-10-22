# Engineering Deep Dive — `FROM` and Base Image Pinning

## Build stages and instructions

`FROM` initializes an image build stage and references its starting image. In this lab, Podman used `registry.access.redhat.com/ubi8/ubi:8.7`. `LABEL` adds image metadata, and `RUN` creates `/tmp/status.txt` within a build layer. Starting a container from the result allows an independent runtime check of that file.

## What does “pinning” really mean?

- `latest`: a conventionally moving tag; not appropriate as a precise build-input identifier.
- `8.7`: a version-specific tag; clearer than `latest`, but the registry can still change the manifest associated with a tag.
- `@sha256:<digest>`: references a particular manifest, and is stronger for reproducibility and provenance. The exact digest must be obtained and verified from the registry for the desired architecture and image variant; none is invented here.

## Practical commands to investigate

```bash
skopeo inspect docker://registry.access.redhat.com/ubi8/ubi:8.7
podman image inspect registry.access.redhat.com/ubi8/ubi:8.7
podman history my-base-image
```

The first command reads registry metadata (using Skopeo), the second inspects the local image, and the third shows image history.

## Build warning interpretation

During the lab, Podman printed ambient capability warnings (`operation not permitted`) while executing the `RUN` instruction. This is not equivalent to a failed build: the output later reported successful tagging and the container successfully printed the file content. A restricted lab host or nested container runtime is one plausible cause, but diagnosing that would require inspecting the environment's security constraints.

## Reproducibility constraints

A fully reproducible production build would also review architecture, package versions, upstream security updates, trusted source policies, and build environment. This small exercise demonstrates version selection and build/runtime validation rather than a complete production supply-chain guarantee.
