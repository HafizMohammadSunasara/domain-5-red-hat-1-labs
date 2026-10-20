# Engineering Proof of Work
### Domain 5 · Linux and Open Source · Red Hat 1

**A growing record of practical container engineering, Linux administration, and reproducible technical learning.**

This evidence framework accompanies my Red Hat 1 learning journal. Its purpose is to make the work behind each completed lab understandable and assessable by engineers, technical reviewers, and recruiters—not simply to display a completion counter.

> **Evidence standard:** I distinguish completed exercises, documented methods, retained artifacts, and independently verified results. A completed lab is not automatically a verified production deployment, a certification, or proof of a passing test.

## What this repository demonstrates

My Red Hat 1 lab practice is built around hands-on exploration of Linux and container tooling. The documented exercises include, as applicable to each lab:

- **Container operations:** working with Podman images, container lifecycle, process behavior, inspection, and controlled cleanup.
- **Networking and storage:** publishing ports, testing local services, configuring bind mounts and volumes, and understanding pod-level networking.
- **Image engineering:** writing Containerfiles, building custom images, using tags, examining build layers, and comparing optimization approaches.
- **Application configuration:** using build arguments, environment variables, environment files, and runtime overrides.
- **Engineering reasoning:** explaining what a command changes, how to validate it, why failures occur, and where a lab exercise differs from production practice.

These examples describe learning areas, **not a claim that every topic has been tested in every environment**. New Red Hat 1 labs and their actual results will extend this record over time.

## How practical work is documented

Each lab's documentation aims to give a reviewer a clear path from objective to verification:

| Evidence element | What a reviewer can evaluate |
| --- | --- |
| **Lab objective and context** | What system behavior or engineering concept the exercise investigates |
| **Original commands and configuration** | How to reproduce the setup, including Containerfiles, scripts, and application files when available |
| **Technical explanation** | Why instructions are used and how the components work together |
| **Validation procedure** | Which commands, responses, or state checks should confirm correct behavior |
| **Troubleshooting and limitations** | Known mistakes, failure modes, assumptions, and corrections |
| **Retained artifacts, when available** | Actual screenshots, logs, outputs, source files, or test reports linked from the relevant lab |

**A documented validation command describes how to test something; it does not, by itself, prove that the test was run or passed.** When output has not been retained, the lab record should say so rather than manufacturing a terminal transcript.

## Evidence status — read the labels carefully

| Label | Meaning |
| --- | --- |
| **Self-reported completed** | I confirm that I performed the lab; original execution evidence may not be publicly attached |
| **Reproducible documentation** | Original instructions, code, and validation steps are available for review or repetition |
| **Artifact attached** | A genuine source file, screenshot, recorded output, or test report is linked and can be inspected |
| **Validated result** | A specific observed outcome is backed by retained test output or other directly reviewable material |
| **Independently verified** | An appropriate independent reviewer or verification process has checked the claimed outcome; never inferred solely from an upload |

These statuses are **not interchangeable**. Source code shows implementation, a test procedure shows intent, and a retained test result supports a concrete outcome.

## How to review my work

1. Open the [Red Hat 1 lab index](../labs/README.md) and select a lab.
2. Read its objective, technical reasoning, command references, and known limitations.
3. Review any original files included in the lab directory, along with linked evidence if present.
4. Follow the stated verification procedure in a suitable isolated Linux/Podman environment, checking image versions and prerequisites first.
5. Compare any observed results against the documented expectations; do not treat example output as a saved execution log.
6. Consult the [progress record](../progress/labs-progress.json) for the current *self-reported* completion count and per-lab status.

The scope of this file is intentionally **evergreen**: it applies to the current labs **and every future lab added under Domain 5 → Linux and Open Source → Red Hat 1**. The individual lab pages and progress data carry the changing details.

## Evidence quality and security commitments

- I publish **original explanations and my own reusable files**, not entire proprietary training handouts.
- I do not invent screenshots, shell output, benchmarks, percentage savings, error logs, or project results.
- I separate **expected output** from **actually observed and retained output**.
- I do not present training exercises as enterprise employment, production ownership, or certification credentials.
- I review artifacts for passwords, tokens, account IDs, private endpoints, personal data, and other sensitive material before sharing.
- I prefer targeted cleanup of lab-created resources instead of destructive commands that remove unrelated containers or images.
- I document known flaws in exercise instructions and corrected reproductions, clearly identifying any changes made after the original session.

## What I want a technical reviewer to see

**I am not using a lab count as a substitute for engineering competence.** I am building a traceable learning record: what I worked on, which tools and concepts were involved, how I reasoned about the system, what can be reproduced, and what has—or has not—been independently evidenced.

For larger independent engineering projects, I maintain separate repositories with deeper architecture, implementation, troubleshooting, and deployment evidence. This repository remains a focused **Red Hat 1 practical learning journal**.

---

**Maintained by:** Hafiz Mohammad Sunasara  
**Track:** Domain 5 — Linux and Open Source / Red Hat 1  
**Lab documentation:** [Browse labs](../labs/README.md) · **Progress:** [View recorded completions](../progress/labs-progress.json)

*This page is the ongoing evidence policy and review guide for the whole Red Hat 1 track. Per-lab evidence and completion status are documented separately and will evolve as new labs are completed.*
