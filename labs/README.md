# Evidence Index — Red Hat 1 Engineering Journal

**Track:** Domain 5 → Linux and Open Source → Red Hat 1  
**Documentation refresh:** 22 October 2026

This folder separates **course-progress indicators**, **GitHub documentation screenshots**, and **direct execution evidence** so technical reviewers can understand exactly what is—and is not—proved.

## Screenshots supplied for the 21 October learning session

Screenshots below are **unaltered copies** of the learner-supplied images. Their dates are grouped by the reported learning session; their original filenames are preserved in the package inventory. Some screenshots were viewed after midnight in the desktop UI.

| Screenshot | Visible content | What it supports | What it does *not* prove |
| --- | --- | --- | --- |
| [Course progress 01–05](screenshots/2026-10-21/alnafi-course-progress-01-05.png) | Al Nafi lab-list completion icons near Labs 01–05 | Course interface shows completed indicators | Commands/output for individual labs |
| [Course progress 06–13](screenshots/2026-10-21/alnafi-course-progress-06-13.png) | Course list displaying completed indicators around Labs 06–13 | Platform progress indicators | Independent lab execution review |
| [Course progress 12–19](screenshots/2026-10-21/alnafi-course-progress-12-19.png) | Course list through Lab 19 and Lab 20 page | Course interface indicates Labs 12–19 completed and Lab 20 is next | Actual Kubernetes resource state or tests |
| [Main README before refresh](screenshots/2026-10-21/github-main-readme-before-update.png) | Main README with outdated 8-lab count | Documentation needed update | Lab performance outcomes |
| [Index before refresh](screenshots/2026-10-21/github-labs-index-before-update.png) | LABS-INDEX only lists through Lab 10 | Navigation needed update | Missing training completion |
| [Journal before refresh](screenshots/2026-10-21/github-journal-before-update.png) | Existing 19 October journal | Previous journal was already published | 21 October technical run logs |
| [Proof-of-work page before refresh](screenshots/2026-10-21/github-evidence-policy-before-update.png) | Existing evidence-policy page | Prior documentation/evidence standard existed | Actual container state |

## Quick visual record

**Course completion UI — through Lab 19**  
![Course interface showing completion indicators through Lab 19](screenshots/2026-10-21/alnafi-course-progress-12-19.png)

**GitHub status prior to repository update**  
![GitHub Labs Index before it was updated](screenshots/2026-10-21/github-labs-index-before-update.png)

The screenshots are **historical snapshots** of the old repository/course UI, not current screenshots of this refreshed README after upload.

## Evidence tiers used here

1. **Learner-confirmed completion:** the user reports running/completing a lab.
2. **Course-platform indicator:** green completion icons show LMS state; they may depend on platform tracking rules.
3. **Repository artifact:** code, YAML, CLI references, and guides show reproducibility, but do not themselves confirm execution.
4. **Direct validation artifact:** a real terminal transcript, test report or screenshot with commands and observed output for a specific experiment. None of the seven screenshots in this batch serve as direct command-result logs.
5. **Independent verification:** third-party review or verifiable automated test results. Not claimed for these labs.

## How to add stronger per-lab evidence later

Prefer **one or two informative images per lab**, not many redundant screenshots: show the exact command plus actual observed outcome. For Kubernetes stateful labs, a good pair would be `kubectl get statefulset,pods,pvc` with Ready/Bound state, and a real query verifying data after Pod recreation. Blur/redact secrets, personal identifiers, internal IPs and tokens *before* sharing new images; do not alter old screenshots and then imply they are originals.

## Related pages

- [Engineering Proof of Work — policy and scope](PROOF-OF-WORK.md)
- [21 October engineering journal](../journals/2026-10-21.md)
- [All 19 lab runbooks](../labs/LABS-INDEX.md)
- [Progress JSON](../progress/labs-progress.json)

**Evidence ethics:** Course badges demonstrate tracked progress, not automatic certification; expected output is not the same as historical observed output.
