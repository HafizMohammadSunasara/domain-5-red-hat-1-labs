# Upload files individually — Domain 5 / Linux and Open Source / Red Hat 1

**Repository:** https://github.com/HafizMohammadSunasara/domain-5-red-hat-1-labs

These are **individual files, not a ZIP**. Download whichever you want to publish. Use the GitHub destination paths below so the links between the README and lab notes keep working.

| Local file | Destination in GitHub |
| --- | --- |
| `README.md` (root) | `README.md` — replace existing starter README |
| `.gitignore` | `.gitignore` |
| `UPLOAD-INSTRUCTIONS.md` | `UPLOAD-INSTRUCTIONS.md` (optional to publish) |
| `journals/2026-10-18.md` | `journals/2026-10-18.md` |
| `labs/README.md` | `labs/README.md` |
| `labs/topic-01-openshift-development/lab-01-introduction-to-containers/README.md` | same path |
| `labs/topic-01-openshift-development/lab-02-exploring-podman-cli/README.md` | same path |
| `labs/topic-01-openshift-development/lab-03-running-containers-with-podman/README.md` | same path |
| `labs/topic-01-openshift-development/lab-04-creating-and-managing-pods/README.md` | same path |
| `labs/topic-01-openshift-development/lab-05-managing-container-images/README.md` | same path |
| `progress/labs-progress.json` | `progress/labs-progress.json` |
| `evidence/README.md` | `evidence/README.md` |

## How to upload using GitHub's website

1. Visit the repository. The root `README.md` already exists: click it, then **Edit** (pencil icon), and replace its content with the downloaded root README (open the file in a text editor and copy/paste). Commit it.
2. For each other file, navigate to its **destination folder** in GitHub and choose **Add file → Upload files**. Upload only that folder's intended file and commit. **Several files are named `README.md`, so never upload all of them to the repository root.**
3. To create a **new folder** in GitHub's web UI: choose **Add file → Create new file**, type its full relative path (e.g., `labs/topic-01-openshift-development/lab-01-introduction-to-containers/README.md`), and paste the contents of the corresponding downloaded file. When you commit it, GitHub creates the required folders automatically. This can be easier than uploading separate local folders.
4. If using your computer instead, you can clone the repo, make the directory structure shown above, copy each downloaded file into the matching path, then run `git add .`, `git commit -m "docs: publish Red Hat 1 labs 01-05"`, and `git push origin main`.

### Which files matter most?

- **Core (8 files):** root `README.md`, five lab-specific `README.md` files, `journals/2026-10-18.md` and `progress/labs-progress.json`.
- **Helpful extras (4 files):** `labs/README.md` for navigation, `evidence/README.md` for screenshot guidelines, `.gitignore`, and this upload guide.

## Progress accuracy

Lab 01–05 completion is **self-reported** by the learner. Lab 06 has **not** been completed and is excluded. No screenshots are included in these documentation files. The JSON does not update your website until its code explicitly reads it.
