# Domain 5 — Linux and Open Source / Red Hat 1

**Hands-on Linux container engineering with Podman**  
**Learning journal · Updated 19 October 2026**

This repository contains my original notes and reproducible examples from **Domain 5 → Linux and Open Source → Red Hat 1**. It documents practical study rather than professional work experience or certification.

> **8 labs completed (self-reported).** Actual screenshots and execution logs are limited; the sample commands and code in this repository are reproducibility materials, not historical audit logs.

## Lab progress

| Lab | Topic | Status |
| --- | --- | --- |
| [01](labs/lab-01-introduction-to-containers/README.md) | Introduction to Containers | Completed — self-reported |
| [02](labs/lab-02-exploring-podman-cli/README.md) | Exploring Podman CLI | Completed — self-reported |
| [03](labs/lab-03-running-containers-with-podman/README.md) | Running Containers with Podman | Completed — self-reported |
| [04](labs/lab-04-creating-and-managing-pods/README.md) | Creating and Managing Pods | Completed — self-reported |
| [05](labs/lab-05-managing-container-images/README.md) | Managing Container Images | Completed — self-reported |
| [06](labs/lab-06-building-custom-container-images/README.md) | Building Custom Container Images | Completed — self-reported |
| [07](labs/lab-07-layer-caching-and-optimization/README.md) | Layer Caching and Optimization | Completed — self-reported |
| [08](labs/lab-08-environment-variables-in-images/README.md) | Environment Variables in Images | Completed — self-reported |

## Engineering journal

- [18 October 2026 — Labs 01–05](journals/2026-10-18.md)
- [19 October 2026 — Labs 06–08](journals/2026-10-19.md)
- [Lab index](labs/README.md)
- [Progress JSON](progress/labs-progress.json)
- [Engineering Proof of Work](evidence/PROOF-OF-WORK.md)

## Recent concepts

- Building and tagging custom Nginx images via Podman and `Containerfile`.
- Understanding immutable image layers, build cache and size-analysis trade-offs.
- Build/runtime variable scoping with `ENV`, `ARG`, `-e` and `--env-file`.
- Diagnosing why an echo-based container exits even with detached mode.

## Evidence and ethics

All completion counts are learner-confirmed. Original logs or screenshots for Labs 06–08 were not preserved. Each lab folder includes original explanatory notes and reference commands/source files that can be rerun, but these are not misrepresented as historical execution evidence. Any metrics must come from actual measurements. The training provider's full proprietary lab handouts are not reproduced.

**Next:** Lab 09. The separate Cloudline AWS project belongs in its independent project repository.
