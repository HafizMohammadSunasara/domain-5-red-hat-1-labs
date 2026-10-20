# Domain 5 — Linux and Open Source / Red Hat 1

**Hands-on Linux container engineering with Podman**  
**Engineering lab journal · Updated 20 October 2026**

I'm documenting **hands-on Linux and Red Hat 1 learning** through concise lab runbooks, deeper technical explanations, and original reproducible configurations. This is a transparent training journal—not a claim of paid enterprise experience or professional certification.

> **8 labs completed (self-reported).** Lab 09 documentation is prepared, but completion has **not yet been confirmed**. Code examples and expected outputs are reproducibility references, not preserved historical execution logs.

## Start here — Technical highlights

**For recruiters and technical reviewers:** Start with the practical engineering concepts below, then use the full lab index to explore the complete learning record.

| Highlight | What it demonstrates | Read |
| --- | --- | --- |
| Container lifecycle | Why detached containers can still exit; process lifetime | [Lab 02](labs/lab-02-exploring-podman-cli/README.md) |
| Container networking & storage | Nginx, port publishing, bind mounts and practical validation | [Lab 03](labs/lab-03-running-containers-with-podman/README.md) |
| Custom image engineering | Containerfile instructions and packaging website content | [Lab 06](labs/lab-06-building-custom-container-images/README.md) |
| Image caching & optimization | Comparing initial, optimized and multi-stage approaches | [Lab 07](labs/lab-07-layer-caching-and-optimization/README.md) |
| Startup process design | ENTRYPOINT, CMD, overrides, shell vs exec, PID 1 | [Lab 09 practical](labs/lab-09-using-entrypoint-and-cmd/README.md) · [Deep dive](labs/lab-09-using-entrypoint-and-cmd/DEEP-DIVE.md) |

Lab 09 is listed as **documentation in progress**, not a completed lab. Future highlights will be selected for engineering relevance rather than trying to feature every entry.

## Progress and navigation

- **Completed:** 8 learner-confirmed labs (01–08)
- **Current:** Lab 09 — Using ENTRYPOINT and CMD in Containerfiles (documentation prepared; completion awaiting confirmation)
- [Browse all labs and statuses](labs/README.md)
- [18 October 2026 — Labs 01–05](journals/2026-10-18.md)
- [19 October 2026 — Labs 06–08](journals/2026-10-19.md)
- [Machine-readable progress](progress/labs-progress.json)
- [Engineering Proof of Work](evidence/PROOF-OF-WORK.md)

## How each new lab is documented

Beginning with **Lab 09**, each lab folder follows a two-level structure:

- **`README.md` — Practical Runbook:** setup, tasks, original concepts, reusable commands, expected observations, troubleshooting and cleanup.
- **`DEEP-DIVE.md` — Engineering Explanation:** conceptual model, internals, why it works, common pitfalls, real-world engineering scenarios and review questions.
- **Source files:** Containerfiles, scripts, app files and other reproducible material when relevant.

This format is designed for fast revision **and** deeper review; labs 01–08 remain in their existing format.

## Evidence and accuracy

Every completion is marked **self-reported** unless stronger proof is attached. A reusable configuration, expected output or explanation does not independently prove the associated lab was executed successfully. No missing screenshots, test logs, benchmarks or results are invented. Training-provider handouts are not reproduced verbatim.

For independently completed, end-to-end engineering projects, see the owner's separate repositories; this repository is exclusively **Domain 5 → Linux and Open Source → Red Hat 1**.

**Maintained by:** Hafiz Mohammad Sunasara · **GitHub:** [HafizMohammadSunasara](https://github.com/HafizMohammadSunasara)
