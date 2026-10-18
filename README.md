# Domain 5 — Linux and Open Source / Red Hat 1

**Hands-on Linux container engineering with Podman**  
**Learning journal • 18 October 2026**

This repository documents my practical learning in **Domain 5 → Linux and Open Source → Red Hat 1**. It contains original technical notes, reusable command references, troubleshooting lessons and a daily progress journal.

> These are **training labs**, not independently delivered production projects or certification claims. Completion is **self-reported** unless supporting results are publicly attached and independently checked.

## Progress

**5 labs completed (self-reported) · Lab 06 scheduled for the next session**

| Lab | Topic | Status | Notes |
| --- | --- | --- | --- |
| [01](labs/lab-01-introduction-to-containers/README.md) | Introduction to Containers | ✅ Completed — self-reported | Containers, Alpine, process lifetime |
| [02](labs/lab-02-exploring-podman-cli/README.md) | Exploring Podman CLI | ✅ Completed — self-reported | Inspect, stop, start, cleanup |
| [03](labs/lab-03-running-containers-with-podman/README.md) | Running Containers with Podman | ✅ Completed — self-reported | Nginx, publishing ports, bind mounts |
| [04](labs/lab-04-creating-and-managing-pods/README.md) | Creating and Managing Pods | ✅ Completed — self-reported | Nginx + Redis, shared networking and storage |
| [05](labs/lab-05-managing-container-images/README.md) | Managing Container Images | ✅ Completed — self-reported | Search, pull, inspect, tags, remove |
| 06 | Building Custom Container Images | ⏳ Planned | Not counted in completed total |

## Repository navigation

- [18 October 2026 — Daily engineering journal](journals/2026-10-18.md)
- [Individual lab notes](labs/)
- [Machine-readable progress — JSON](progress/labs-progress.json)
- [Evidence submission guide](evidence/README.md)
- [Manual GitHub upload instructions](UPLOAD-INSTRUCTIONS.md)

## Technical lessons

- Detached mode (`-d`) changes terminal attachment, not the lifetime of the main container process.
- Containers created from the same image can have different names, ports, mounts and lifecycle states.
- A published host port is not the same thing as an application listening inside a container.
- Bind mounts expose existing host files; changes to those files can appear immediately in the container.
- Containers in one Podman pod typically share a network namespace, **not automatically the same files**.
- Image tags identify references/versions, but a mutable tag such as `latest` is not a fixed digest.
- Cleanup should target lab-created resources instead of deleting unrelated containers or images.

## Verification and publication standards

- **Completion count:** user-confirmed exercises, not audited results.
- **Screenshots:** two screenshots for Lab 03 were captured locally, but are **not included** here. No proof images are fabricated.
- **Originality:** summaries and command examples are original learning notes; this repo does not reproduce proprietary course handouts.
- **Safety:** review screenshots for passwords, access tokens, credentials, personal information and account identifiers before public upload.
- **Scope:** Only Domain 5 / Linux and Open Source / Red Hat 1. Other domains and portfolio projects belong in separate repositories.

---

**Maintained by:** Hafiz Mohammad Sunasara  
**Learning focus:** Linux, Podman, container operations and practical DevOps fundamentals.
