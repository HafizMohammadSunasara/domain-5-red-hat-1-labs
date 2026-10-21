# Linux, Containers & Kubernetes | Engineering Lab Journal

**Domain 5 · Linux and Open Source · Red Hat 1**  
**Maintained by Hafiz Mohammad Sunasara**

**19 documented labs (completed — self-reported)** · **9 labs reported on 21 October 2026** · **Podman → Compose → Kubernetes**

> **My focus:** Don't just get a container running. Understand its lifecycle, trace failures, preserve data, and document how to recover.

This repository is a structured record of my hands-on Cloud & DevOps training. It brings together practical runbooks, reproducible configuration files, technical explanations, and known limitations. It is a **learning journal**, not a claim of enterprise production experience or an industry certification.

**[Explore all 19 labs](labs/LABS-INDEX.md)** · **[Selected engineering work](#selected-engineering-work)** · **[Daily engineering journal](journals/2026-10-21.md)** · **[Evidence gallery](evidence/README.md)**

---

## What I'm building competence in

| Engineering area | Practical coverage | Labs |
| --- | --- | --- |
| **Container foundations** | Image and container lifecycle, Podman CLI, pods, image layers, build configuration, `ENTRYPOINT` and `CMD` | 01–09 |
| **Storage & recovery** | Named volumes, bind mounts, MySQL/PostgreSQL persistence, logical backups and restore | 10–12 |
| **Diagnosis & connectivity** | Logs, inspection, resource statistics, network troubleshooting, Node.js remote debugging | 13–15 |
| **Multi-container systems** | Compose services, dependency order, replica scaling, Flask-to-Redis connectivity | 16–17 |
| **Kubernetes workloads** | Pod manifests, `kubectl` diagnostics, StatefulSets, headless Services and per-Pod PVCs | 18–19 |

## Selected engineering work

If you're reviewing this repository for a junior Cloud/DevOps opportunity, these entries show the reasoning and configurations behind the exercises—not only completion counts.

| Explore | Engineering question | What to inspect |
| --- | --- | --- |
| **[Lab 19 — Kubernetes StatefulSets](labs/lab-19-deploying-statefulsets/README.md)** | What happens to a MySQL Pod's identity and data after recreation? | [StatefulSet manifest](labs/lab-19-deploying-statefulsets/mysql-statefulset.yaml) · [Headless Service](labs/lab-19-deploying-statefulsets/mysql-service.yaml) · [Deep dive](labs/lab-19-deploying-statefulsets/DEEP-DIVE.md) |
| **[Lab 18 — Kubernetes Pod Deployment](labs/lab-18-kubernetes-pod-deployment/README.md)** | How do you declare, deploy and inspect a Pod? | [Nginx Pod YAML](labs/lab-18-kubernetes-pod-deployment/simple-pod.yaml) · [Deep dive](labs/lab-18-kubernetes-pod-deployment/DEEP-DIVE.md) |
| **[Lab 17 — Compose Dependencies](labs/lab-17-compose-with-dependencies/README.md)** | Does startup order guarantee service readiness? How do replicas communicate? | [Flask app](labs/lab-17-compose-with-dependencies/app.py) · [Compose YAML](labs/lab-17-compose-with-dependencies/docker-compose.yml) · [Deep dive](labs/lab-17-compose-with-dependencies/DEEP-DIVE.md) |
| **[Lab 12 — Database Backup & Restore](labs/lab-12-backup-and-restore-data/README.md)** | Is persistent storage the same as having a recoverable backup? | Dump/restore runbook · [Deep dive](labs/lab-12-backup-and-restore-data/DEEP-DIVE.md) |
| **[Lab 15 — Remote Container Debugging](labs/lab-15-remote-debugging-of-containers/README.md)** | How can an IDE inspect a running application's execution? | [Node.js sample](labs/lab-15-remote-debugging-of-containers/app.js) · [VS Code attach config](labs/lab-15-remote-debugging-of-containers/.vscode/launch.json) · [Deep dive](labs/lab-15-remote-debugging-of-containers/DEEP-DIVE.md) |
| **[Lab 13 — Container Troubleshooting](labs/lab-13-troubleshooting-containers/README.md)** | Which tools answer questions about process state, logs and resource usage? | Podman diagnostics runbook · [Deep dive](labs/lab-13-troubleshooting-containers/DEEP-DIVE.md) |

**Important engineering distinctions:** A PVC is **not** a backup. A StatefulSet does **not** automatically replicate MySQL data. Compose `depends_on` does **not** by itself mean a service is ready. These limitations matter beyond the happy-path lab result.

## How to review the labs

- **Practical runbook (`README.md`):** objectives, source commands, expected behavior, validation steps, troubleshooting and corrections.
- **Engineering deep dive (`DEEP-DIVE.md`, Labs 09–19):** what happens internally, why a command works, failure modes and real-world trade-offs.
- **Source artifacts:** Containerfiles, Compose files, Python/Node.js examples and Kubernetes manifests where relevant.
- **Evidence and status:** labels distinguish learner-reported completion, course progress screenshots and directly retained test results.

Start with the **[complete lab index](labs/LABS-INDEX.md)** to browse Labs 01–19 in order.

## Learning log

| Date | Reported progress | Journal |
| --- | --- | --- |
| **18 Oct 2026** | Labs 01–05: Podman and container foundations | [Read](journals/2026-10-18.md) |
| **19 Oct 2026** | Labs 06–08: image builds, caching and configuration | [Read](journals/2026-10-19.md) |
| **21 Oct 2026** | Labs 11–19: stateful data, debugging, Compose and Kubernetes | [Read](journals/2026-10-21.md) |

Labs 09–10 are included in the lab index and overall self-reported progress. The session table above highlights the existing dated journal entries rather than attributing unverified dates to every lab.

## Evidence, scope & transparency

**Progress:** 19 lab exercises are documented and marked **completed — self-reported** in the [lab index](labs/LABS-INDEX.md) and [structured progress record](progress/labs-progress.json). Course-platform screenshots are available in the [evidence gallery](evidence/README.md).

**What the screenshots show:** the training platform's completion indicators. **What they do not show:** an independently audited terminal result for every lab. Sample outputs in runbooks are explicitly examples unless backed by retained execution artifacts.

See the [Engineering Proof of Work](evidence/PROOF-OF-WORK.md) for the evidence standard, reproducibility approach, and limitations.

**Next:** Lab 20 — Service and Ingress Setup (not yet counted as completed).

---

**Hafiz Mohammad Sunasara** · Cloud & DevOps Engineering Learner  
[GitHub profile](https://github.com/HafizMohammadSunasara) · [LinkedIn](https://www.linkedin.com/in/hafiz-mohammad-sunasara-118756366/)

*Updated: 22 October 2026 · Domain 5 / Linux and Open Source / Red Hat 1*
