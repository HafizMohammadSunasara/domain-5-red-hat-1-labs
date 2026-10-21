# Engineering Proof of Work
### Domain 5 · Linux and Open Source · Red Hat 1

**A growing, traceable record of practical Linux/container engineering and Kubernetes learning.**

The purpose of this evidence framework is to make my learning **reviewable and reproducible**, not simply to display a completion counter. It applies to all current and future Red Hat 1 labs.

> **Evidence standard:** I distinguish (1) learner-reported completion, (2) the training portal's completion state, (3) published code and documentation, (4) actually retained execution results, and (5) independent verification. These are not interchangeable.

## Current scope

This journal covers **Labs 01–19, completed — self-reported**. The learner reported finishing Labs 11–19 during the 21 October 2026 session. Course-interface screenshots show completion indicators; no claim is made that the screenshot set independently proves every technical task succeeded.

### Topics and inspectable artifacts

| Area | Skills/practical artifacts |
| --- | --- |
| **Container lifecycle & image engineering** | Podman CLI, process lifetime, Containerfiles, images, layers, ENV/ARG, ENTRYPOINT/CMD |
| **Networking and persistent storage** | Bridge networks, published ports, Podman pods, named volumes, bind mounts, Nginx |
| **Stateful databases & data recovery** | MySQL and PostgreSQL local persistence, SQL dump and restore concepts |
| **Debugging and observability** | Podman logs, inspect, resource stats, interactive exec and Node.js remote debugging |
| **Compose orchestration** | Multi-container Nginx/PostgreSQL, depends_on, scaling, Flask-Redis communication |
| **Kubernetes workloads** | Pod YAML, kubectl workflows, StatefulSet, headless Service, stable Pod identity and PVCs |

These are **documented learning areas**, not statements of production readiness or third-party validated competence.

## Evidence available today

See the **[evidence gallery](README.md)** for the seven original screenshot files supplied by the learner.

- **Course platform screenshots:** show checked/completed items across Labs 01–19 and the Lab 20 lesson. This supports the platform's displayed progress at capture time.
- **GitHub screenshots:** show the existing README, Labs Index, journal and evidence policy **before** this refresh. They prove those repository pages existed and that their progress text was outdated—not that Kubernetes or MySQL tests independently passed.
- **Lab directories:** scripts, YAML manifests, SQL commands, source code and runbooks provide concrete implementation references and a reproducibility path.
- **No command-result transcript included in the supplied screenshot batch:** commands and sample outputs in guides should be treated as instructions/expectations unless separately supported.

## How practical work is documented

| Evidence element | What a reviewer can evaluate |
| --- | --- |
| **Lab objective and context** | What the exercise investigates and prerequisite environment |
| **Runbook (`README.md`)** | Commands, configuration, expected outcome, verification, troubleshooting and cleanup |
| **Deep Dive (`DEEP-DIVE.md`)** | Internal mechanisms, caveats, design alternatives and real-world analogies |
| **Reproducible source** | Containerfiles, Dockerfiles, Python/Node code, Compose and Kubernetes YAML |
| **Screenshot or log** | Only the specific result visibly retained in that artifact |
| **Limitations and corrections** | Known instructor inconsistencies, environmental assumptions and safety constraints |

An instruction to run `kubectl get pods` is **not** a preserved screenshot showing the Pod running. Similarly, code uploaded to GitHub is not proof that the code was executed on a specific day.

## Evidence labels — precise meanings

| Label | Interpretation |
| --- | --- |
| **Completed — self-reported** | Learner says the exercise was completed |
| **Course-progress indicator** | Training platform displays completed/checkmarked status |
| **Reproducible documentation** | Source and steps are available for a reviewer to attempt |
| **Direct execution evidence** | Actual terminal output, log, screenshot or test artifact shows a particular observed result |
| **Independently verified** | A separate reviewer or suitable automated process reviewed that claim; never inferred from a badge or screenshot alone |

## Review workflow for recruiters and engineers

1. Browse the [complete lab index](../labs/LABS-INDEX.md), selecting a relevant practical lab.
2. Open the lab's files and any Deep Dive to inspect design decisions and reproducibility.
3. Read the [21 October journal](../journals/2026-10-21.md) for session context and limits.
4. Examine the [screenshot gallery](README.md) and the scope of each image's claim.
5. Re-run commands, inspect actual resources and test expected outcomes in a suitable isolated environment.
6. Check the [progress JSON](../progress/labs-progress.json) for per-lab dates and self-reported status.

## Technical accuracy and security commitments

- No invented shell output, screenshots, measured benefits, passing tests or production ownership.
- No claim that a StatefulSet with two MySQL Pods automatically configures database replication.
- No claim that a PVC is a backup or that Compose startup order guarantees service readiness.
- Clearly mark examples and corrected variants separately from original instructor instructions.
- Do not publish passwords, real secrets, credentials, kubeconfig tokens or private endpoints.
- Prefer reproducible source, command/result pairs and documented limitations over a raw lab-count competition.

## Next evidence improvement

For upcoming labs, capture **1–2 genuine, redacted command-and-output images** per significant outcome and link them from the corresponding lab README. A passing test is more useful to reviewers when its commands, environment context and actual result are visible.

---

**Maintainer:** Hafiz Mohammad Sunasara  
**Lab index:** [Labs 01–19](../labs/LABS-INDEX.md) · **Images:** [Evidence gallery](README.md) · **Progress:** [Structured record](../progress/labs-progress.json)
