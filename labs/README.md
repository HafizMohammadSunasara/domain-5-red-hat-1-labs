# Lab 06 — `CMD` vs `ENTRYPOINT` | Podman Container Startup Engineering

**Domain 5 → Linux and Open Source → Red Hat 1 → Topic 2: Red Hat Certified Specialist in Containers**  
**Lab date:** 24 October 2026  
**Status:** Practical tasks completed (learner-reported); **five original terminal screenshots retained**  
**Environment:** Al Nafi Ubuntu training terminal · Podman · Alpine Linux  
**Primary skills:** Containerfile authoring · runtime overrides · process execution · shell startup wrappers · validation

> **Engineering takeaway:** `CMD` supplies a replaceable default. Exec-form `ENTRYPOINT` selects the executable. When they are combined, `CMD` supplies that executable's default arguments. Runtime behavior—not only a successful build—is the proof.

**[Full beginner-to-advanced handbook → DEEP-DIVE.md](DEEP-DIVE.md)** · [Evidence gallery](#actual-execution-evidence) · [Reproduce the lab](#reproduce-step-by-step) · [Troubleshooting](#troubleshooting)

---

## 1. Why this lab matters

A container image is not just a filesystem. It also describes **what process starts** when a container is launched. If an image chooses the wrong default process, ignores runtime arguments, or uses a shell wrapper that does not forward signals correctly, it can behave unexpectedly under Podman, Docker, or a future Kubernetes workload.

This lab answers four practical questions:

1. How do we run a command automatically when a container starts?
2. How can we replace a default command without rebuilding the image?
3. How do we keep the *program* fixed but change its *arguments*?
4. How can a startup script prepare the environment and then hand control to the real process?

These are controlled training demonstrations with `echo`, `ls`, and a small shell script—not a production deployment or performance benchmark.

## 2. Results at a glance

| Exercise | Configuration | Runtime experiment | What the retained screenshot demonstrates |
|---|---|---|---|
| **Task 1 — CMD** | `CMD ["echo", "hello from cmd"]` | Add `echo "Overridden command"` after image name | Default prints; supplied command replaces it |
| **Task 2 — ENTRYPOINT** | `ENTRYPOINT ["echo", "hello from ENTRYPOINT"]` | Supply `"with appended text"` | Extra text is appended to the executable's arguments |
| **Task 3 — Combined** | `ENTRYPOINT ["echo"]` + `CMD ["DEFAULT MESSAGE"]` | Run with `"costum message"` (typed in the session) | Default argument replaced by a supplied argument; screenshots reflect original typing |
| **Task 4 — Script** | `/entrypoint.sh` plus default `echo` | Run wrapper, then override with `/bin/ls -l /` | Script default output and bypass of default entrypoint are visible |
| **Final image check** | Four tagged builds | `podman images` | All four images are listed in the training environment |

**Observed sizes:** In the final screenshot, `cmd-demo`, `entrypoint-demo`, and `combined-demo` are shown near **8.71 MB**, while `script-demo` is near **8.72 MB**. These are point-in-time local Podman display values, not a controlled size benchmark.

## 3. Actual execution evidence

The following five screenshots are from the learner's real course session on **24 October 2026**. Images have been **upscaled 2× and gently sharpened** for readability; they are not synthetic command output. Click any image to open it full size.

### Evidence 01 — CMD build, default, override

[![CMD build and override terminal results](evidence/01-cmd-default-and-override.png)](evidence/01-cmd-default-and-override.png)

The terminal shows a successful `cmd-demo` build, a default message, and the output `Overridden command` after a runtime override.

### Evidence 02 — ENTRYPOINT build and appended argument

[![ENTRYPOINT default and appended argument results](evidence/02-entrypoint-default-and-arguments.png)](evidence/02-entrypoint-default-and-arguments.png)

The terminal shows `entrypoint-demo` created and then output from the base `ENTRYPOINT` and with appended text.

### Evidence 03 — Combined instructions

[![Combined ENTRYPOINT and CMD build with overridden output](evidence/03-combined-build-and-output.png)](evidence/03-combined-build-and-output.png)

The course screenshot records building `combined-demo`, printing `DEFAULT MESSAGE`, and accepting a custom runtime message.

### Evidence 04 — Shell wrapper and complete entrypoint override

[![Shell entrypoint and override results](evidence/04-script-and-entrypoint-override.png)](evidence/04-script-and-entrypoint-override.png)

The screenshot shows script startup output (`Starting container with arguments: echo Default execution`), `Default execution`, and a root-directory listing when `--entrypoint /bin/ls` is supplied.

### Evidence 05 — Four built images

[![Image inventory showing four completed lab images](evidence/05-final-images-verification.png)](evidence/05-final-images-verification.png)

The `podman images` listing shows `cmd-demo`, `entrypoint-demo`, `combined-demo`, and `script-demo` together.

> **Evidence integrity:** The images prove the visible build and runtime results, but they are not an unedited terminal transcript or a security audit. The Containerfiles below are reproducible **reconstructions consistent with the course and visible commands**. The original files were not directly exported from the ephemeral training instance. The exact optional final message `Lab completed successfully!` is in the course instructions but is **not independently visible** in the five retained screenshots.

---

## 4. Core mental model

```text
Container image build
  ├── filesystem + installed software
  └── image startup configuration
        ├── ENTRYPOINT = primary executable (when set)
        └── CMD        = default command OR default arguments
                               │
Podman starts a container      │
  └── podman run IMAGE [user-supplied-command-or-arguments]
        ├── CMD only: replaces CMD with supplied command/args
        └── Exec-form ENTRYPOINT: appends supplied arguments to ENTRYPOINT
             └── --entrypoint explicitly replaces ENTRYPOINT
```

**Memorable analogy:** `ENTRYPOINT` is the tool (`python`, `nginx`, or `echo`); `CMD` is the default instruction handed to that tool. Without `ENTRYPOINT`, `CMD` can define the whole default command.

### Quick comparison

| Behavior | CMD only | ENTRYPOINT only | Combined (exec form) |
|---|---|---|---|
| Starts automatically? | Yes | Yes | Yes |
| Default executable | From CMD | From ENTRYPOINT | From ENTRYPOINT |
| Arguments after image name | Replace default CMD | Append to ENTRYPOINT | Replace CMD arguments and append to ENTRYPOINT |
| Explicit full override | New command after image | Use `--entrypoint` | Use `--entrypoint` |

*Scope:* This table describes the **exec/JSON-array form** used in this lab. Shell-form behavior differs. See [Deep Dive](DEEP-DIVE.md#4-exec-form-versus-shell-form).

---

## 5. Reproduce step by step

### Prerequisites

A Linux shell, rootless or otherwise working Podman installation, and internet access to pull `docker.io/library/alpine:latest`.

```bash
podman --version
mkdir -p ~/cmd-entrypoint-lab
cd ~/cmd-entrypoint-lab
```

Put the five source files from this directory (`Containerfile.cmd`, `Containerfile.entrypoint`, `Containerfile.combined`, `Containerfile.script`, `entrypoint.sh`) in the same working directory. If downloaded from GitHub, use a clone so they remain together.

> **Build context correction:** Include a final `.` in every `podman build` command; the `.` refers to the current directory containing the selected Containerfile and any files to be copied.

### Task 01 — `CMD`: default command + runtime replacement

File: [`Containerfile.cmd`](Containerfile.cmd)

```dockerfile
FROM docker.io/library/alpine:latest
CMD ["echo", "hello from cmd"]
```

```bash
podman build -t cmd-demo -f Containerfile.cmd .
podman run --rm cmd-demo
podman run --rm cmd-demo echo "Overridden command"
```

**Expected from these included files:**

```text
hello from cmd
Overridden command
```

**Why:** Podman uses the configured CMD when no command is supplied; a command after `cmd-demo` replaces it. Nothing here requires rebuilding the image between runs.

### Task 02 — `ENTRYPOINT`: executable with appended runtime arguments

File: [`Containerfile.entrypoint`](Containerfile.entrypoint)

```dockerfile
FROM docker.io/library/alpine:latest
ENTRYPOINT ["echo", "hello from ENTRYPOINT"]
```

```bash
podman build -t entrypoint-demo -f Containerfile.entrypoint .
podman run --rm entrypoint-demo
podman run --rm entrypoint-demo "with appended text"
```

**Expected:**

```text
hello from ENTRYPOINT
hello from ENTRYPOINT with appended text
```

**Why:** `ENTRYPOINT` is the selected process; normal runtime values are its additional arguments. Note: `ENTRYPOINT` isn't a security lock—`--entrypoint` can override it.

### Task 03 — `ENTRYPOINT` plus `CMD`: stable executable, flexible arguments

File: [`Containerfile.combined`](Containerfile.combined)

```dockerfile
FROM docker.io/library/alpine:latest
ENTRYPOINT ["echo"]
CMD ["DEFAULT MESSAGE"]
```

```bash
podman build -t combined-demo -f Containerfile.combined .
podman run --rm combined-demo
podman run --rm combined-demo "Custom message"
```

**Expected:**

```text
DEFAULT MESSAGE
Custom message
```

**Why:** The runtime doesn't replace the `echo` executable here. It replaces the *default argument* defined by CMD. The historical screenshot uses the typed text `costum message`; the reproducible example uses corrected spelling.

### Task 04 — Startup script, `exec`, and complete override

Files: [`entrypoint.sh`](entrypoint.sh) and [`Containerfile.script`](Containerfile.script).

```sh
#!/bin/sh
echo "Starting container with arguments: $@"
exec "$@"
```

```dockerfile
FROM docker.io/library/alpine:latest
COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["echo", "Default execution"]
```

```bash
podman build -t script-demo -f Containerfile.script .
podman run --rm script-demo
podman run --rm --entrypoint /bin/ls script-demo -l /
```

**Expected default:**

```text
Starting container with arguments: echo Default execution
Default execution
```

The second run lists `/` instead. It uses `/bin/ls` directly rather than executing the default entrypoint script.

**Why `exec "$@"` matters:** It replaces the wrapper shell with the specified command while preserving argument boundaries. In long-running services, that helps the primary process receive container lifecycle signals directly.

### Final inventory and cleanup

```bash
podman images
podman run --rm combined-demo "Lab completed successfully!"
```

You should see the four custom images in the inventory, then the final success message. **The final success-message command above is a suggested reproducibility check, not an additional claim about the archived screenshots.**

When finished, remove images if no longer needed:

```bash
podman rmi cmd-demo entrypoint-demo combined-demo script-demo
```

Don't remove the project files from your GitHub clone.

---

## 6. Troubleshooting

| Symptom | Likely reason | Investigation / fix |
|---|---|---|
| `podman build` says it needs a context | Missing final `.` | Use `podman build -f Containerfile.cmd -t cmd-demo .` |
| Script says `permission denied` | Missing execute bit in image | `RUN chmod 0755 /entrypoint.sh` |
| `exec format error` | Missing `#!/bin/sh`, wrong architecture or Windows CRLF | Check shebang; convert to LF line endings |
| `no such file or directory` for script | Wrong build context/path or CRLF in shebang | Confirm `COPY` and `file entrypoint.sh` |
| Runtime input seems to replace `ENTRYPOINT` | Shell-form/exec-form confusion or explicit override | Inspect `podman image inspect IMAGE` and command syntax |
| Container exits immediately | `echo`/`ls` complete quickly | Expected: one-shot containers exit when their main process ends |
| `CMD` text disappears unexpectedly | Passing an argument replaces the entire CMD array | Pass all desired runtime arguments, not only one value |
| Script works locally but not in Kubernetes | Command/args mappings or signal handling | Consult [Deep Dive](DEEP-DIVE.md#12-how-this-maps-to-kubernetes) |

## 7. Engineering decisions and limitations

- **No fabricated proof:** This repository links only to the five supplied, real terminal screenshots.
- **Observed vs expected:** Demonstrated outputs are labeled separately from reproducibility commands.
- **Mutable base tag:** `alpine:latest` follows the course but is not reproducibly pinned. A maintained release and digest would be better for long-lived systems.
- **Not a security claim:** `ENTRYPOINT` does **not** prevent an authorized operator from using `--entrypoint`.
- **Short-lived demo processes:** The `echo` examples intentionally exit; they do not represent an always-on application.
- **Readability editing:** Screenshots are upscaled, not retouched to manufacture success.

## 8. What this prepares me for

- Debugging container startup failures and surprising arguments.
- Designing wrapper scripts for initialization and graceful shutdown.
- Understanding the difference between **image defaults** and **runtime configuration**.
- Mapping startup commands into Kubernetes Pods (`command` and `args`).
- Explaining process PID 1, signal forwarding, and the importance of `exec`.

**Go deeper:** [DEEP-DIVE.md — explanation, experiments, troubleshooting framework, and interview practice](DEEP-DIVE.md).

---

*Maintained as an educational proof-of-work record. Lab completion was learner-reported; the linked screenshots independently support only the visible terminal outcomes. No claim of production experience or Red Hat certification is made.*
