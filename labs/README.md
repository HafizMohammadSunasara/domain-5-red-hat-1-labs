# Lab 07 — Parameterized ENTRYPOINT Scripts | Podman Engineering Journal

**Domain 5 → Linux & Open Source → Red Hat 1 → Topic 2: Red Hat Certified Specialist in Containers**  
**Recorded lab date:** 24 October 2026  
**Environment:** Al Nafi Ubuntu lab · Podman · Alpine Linux  
**Learning outcome:** ENTRYPOINT initialization, parameters, CMD defaults, ENV_MODE, subcommands, and reproducible testing  
**Status:** Lab work reported completed; screenshots retained. Validation is **partial** for Tasks 2–4 (see [Evidence and limitations](#evidence-and-limitations)).

> **Engineering lesson:** Editing a startup script on the host does **not** update an already-built image. Rebuild the image, run an explicit test, and compare the actual output with the expected behavior. A successful command invocation is not, by itself, proof that the intended logic executed.

**[Deep technical handbook](DEEP-DIVE.md)** · **[Start the practical guide](#reproduce-every-task)** · **[Review real screenshots](#evidence-and-limitations)** · **[Troubleshooting](#troubleshooting-playbook)**

---

## The engineering problem

A container is often asked to perform the same core job in more than one environment. During development it may need extra diagnostics. In production it should use predictable settings. A testing job might start with special arguments. We want one image whose **startup behavior is explicit**, easy to inspect, and able to accept configuration at runtime rather than being rebuilt for every option.

This exercise follows an incremental sequence:

```text
Podman run → IMAGE ENTRYPOINT → startup script
                                  ├─ Task 1: identify runtime context
                                  ├─ Task 2: read args, exec requested command
                                  ├─ Task 3: inspect ENV_MODE, exec command
                                  └─ Task 4: dispatch start / stop / invalid
```

Each task below has its **own script and Containerfile** so you can reproduce it independently. This avoids the original lesson's repeated edit-and-rebuild cycle obscuring which version of the script actually ended up in an image.

## Results at a glance

| Task | Intended learning | What the screenshot really supports | Confidence |
|---|---|---|---|
| **01 · Basic script** | ENTRYPOINT automatically launches a script | Successful build and output `Container starting...`, `root`, `/` | **Directly observed** |
| **02 · Parameters** | `$1`, `$2`, `CMD`, and forwarding via `exec "$@"` | Script printed `hello world` as two arguments; the provided screenshot does **not** show a command successfully executed by `exec` | **Argument logging observed; forwarding not proven** |
| **03 · Environment modes** | Switch between development, production, default | Three `podman run` attempts are shown, but **no expected mode banners** appear; the old argument logger still runs | **Mode logic not verified** |
| **04 · Advanced dispatch** | `start`, `stop`, invalid handling | Three commands were invoked; output remained the earlier argument logger, **not** the expected start/stop/usage messages | **Dispatch not verified** |

**Why this matters:** Stating precisely what was and was not observed is stronger evidence than claiming every step succeeded because commands returned a terminal prompt.

---

## Repository files

| File | Purpose |
|---|---|
| [`Containerfile.basic`](Containerfile.basic) · [`entrypoint.basic.sh`](entrypoint.basic.sh) | Task 1: print the startup context |
| [`Containerfile.parameters`](Containerfile.parameters) · [`entrypoint.parameters.sh`](entrypoint.parameters.sh) | Task 2: positional parameters and `exec "$@"` |
| [`Containerfile.modes`](Containerfile.modes) · [`entrypoint.modes.sh`](entrypoint.modes.sh) | Task 3: mode selection via `ENV_MODE` |
| [`Containerfile.commands`](Containerfile.commands) · [`entrypoint.commands.sh`](entrypoint.commands.sh) | Task 4: `start`/`stop` subcommand demonstration |
| [`DEEP-DIVE.md`](DEEP-DIVE.md) | Beginner-to-advanced internals, signal handling, troubleshooting, deployment applications, interview questions |
| [`evidence/`](evidence/) | Four genuine screenshots of the original lesson session, enlarged for legibility |

**Provenance:** Source files are **reconstructed, corrected learning examples** from the user-provided lab material; not exports of the Al Nafi lab machine. The evidence images, by contrast, originate from that real session. They are not generated terminal outputs.

## Reproduce every task

Requirements: Podman with registry access; Linux, Ubuntu VM, or WSL shell. The sample base image is `docker.io/library/alpine:latest` to stay consistent with the course. `latest` is mutable; pin a tested digest for repeatable production releases.

Run the following from **this folder**, which contains all eight source/configuration files:

```bash
podman --version
pwd
ls -l Containerfile.* entrypoint.*.sh
```

### Task 1 — Basic initialization

```bash
podman build -f Containerfile.basic -t lab07-basic .
podman run --rm lab07-basic
```

**Expected output:**

```text
Container starting...
Executing as user: root
Current directory: /
```

**Why it works:** `ENTRYPOINT ["/entrypoint.sh"]` is an exec-form instruction: the container executes the script when it starts. The shebang `#!/bin/sh` uses Alpine's available shell. `whoami` describes the container user, not the laptop's current user; `pwd` prints the process working directory, which is `/` in this simple image.

**What is actually evidenced:** [Task 1 screenshot](evidence/01-basic-entrypoint-build-and-run.png) shows the expected messages.

### Task 2 — Parameterize the startup command

```bash
podman build -f Containerfile.parameters -t lab07-parameters .
podman run --rm lab07-parameters
podman run --rm lab07-parameters ls -l /
podman run --rm lab07-parameters echo "Hello from a custom command"
```

**Expected default result:**

```text
Container starting with arguments: echo Default command executed
First argument: echo
Second argument: Default command executed
Default command executed
```

With `ls -l /`, the first argument becomes `ls`, the second `-l`, and `exec "$@"` executes `ls -l /` instead of the CMD default. With `echo "Hello ..."`, the second argument is one quoted message.

**Important:** In the original screenshot, `podman run entrypoint-demo:latest hello world` printed argument information only. That is not evidence that a command named `hello` successfully executed. A script that *does* include `exec "$@"` would normally fail with a command-not-found status in that exact example. Use `echo hello world` or `ls -l /` for a valid executable.

### Task 3 — Development/production/default modes

```bash
podman build -f Containerfile.modes -t lab07-modes .
podman run --rm -e ENV_MODE=development lab07-modes
podman run --rm -e ENV_MODE=production lab07-modes
podman run --rm lab07-modes
```

**Expected first lines:**

```text
DEVELOPMENT MODE: Debug features enabled (demo message only)
PRODUCTION MODE: Strict settings applied (demo message only)
No ENV_MODE specified, running in default mode
```

Each run should subsequently print `Running container`. This educational script **only prints a mode message**; it does *not* truly enforce different production security policies or enable a real debugger.

**Observed caveat:** The training screenshot shows attempts with `ENV_MODE`, but the response was unchanged argument logging. That suggests the updated mode script was not included in the image actually executed (or the script content differed). Do not report it as proven mode switching until new output is captured.

### Task 4 — Basic command dispatch

```bash
podman build -f Containerfile.commands -t lab07-commands .
podman run --rm lab07-commands
podman run --rm lab07-commands start production
podman run --rm lab07-commands stop
podman run --rm lab07-commands invalid
printf 'Last exit code: %s\n' "$?"
```

**Expected:** Default `start default` displays the configured setting; `start production` prints a production *label*; `stop` prints the stop demo line; `invalid` prints usage and exits `64`. The last command should display `64` if executed immediately after the invalid call. A nonzero status for the invalid command is the intentional result.

**Critical distinction:** These commands create *separate, short-lived* containers. `podman run ... stop` does not stop a long-running `podman run ... start` container; it is only a `case`-statement dispatch demonstration. Real service lifecycle control uses process signals, a supervisor, or orchestrator APIs.

**Observed caveat:** In the original [Task 4 screenshot](evidence/04-start-stop-invalid-attempts.png), the old parameter-logging behavior appears, rather than these dispatch outputs. Rebuild or use this task-specific image to verify the corrected behavior.

### Extra validation commands

```bash
podman image inspect lab07-parameters --format '{{json .Config.Entrypoint}}'
podman image inspect lab07-parameters --format '{{json .Config.Cmd}}'
podman image inspect lab07-modes --format '{{json .Config.Entrypoint}}'
podman run --rm --entrypoint /bin/sh lab07-modes -c 'printf "mode=%s\\n" "${ENV_MODE:-unset}"'
```

The final command **intentionally bypasses** the entrypoint, showing that `--entrypoint` changes which startup executable runs. Don't confuse that output with the actual mode-script path.

---

## Evidence and limitations

These are the **actual screenshots submitted from 24 October 2026**, lightly sharpened and scaled to 1.5× so GitHub readers can inspect them. No commands or terminal output were added, removed, or fabricated.

### 01 — Basic ENTRYPOINT execution

[![Basic startup script build and output](evidence/01-basic-entrypoint-build-and-run.png)](evidence/01-basic-entrypoint-build-and-run.png)

Confirms a successful `podman build --no-cache` and a working basic startup script. Note the screenshot shows the working location `~`; the course's example may use `~/entrypoint-lab`. The reproduction instructions use the repository directory containing the source files.

### 02 — Argument logging

[![Parameter handling, hello world argument logging](evidence/02-parameter-handling-observed.png)](evidence/02-parameter-handling-observed.png)

Shows image build with `CMD` and argument labels for `hello` and `world`. Does **not** prove the final command was invoked via `exec`.

### 03 — Environment-mode run attempts

[![Development production default mode command attempts](evidence/03-environment-mode-attempts.png)](evidence/03-environment-mode-attempts.png)

The run flags differ, but the script output does not include any development or production branch banners. The terminal also shows a shebang edit and an `awk` warning; these do not prove the mode logic entered the image.

### 04 — Start, stop and invalid argument attempts

[![Task 4 start stop invalid attempts](evidence/04-start-stop-invalid-attempts.png)](evidence/04-start-stop-invalid-attempts.png)

`start production`, `stop`, and `invalid` were passed as runtime arguments; the observed response matches earlier parameter-logging logic instead of the dispatch script. This is a useful example of **stale image vs edited source**.

### Validation matrix

| Claim | Captured proof | Follow-up if required |
|---|---|---|
| Script runs at container start | Yes — Task 1 | None |
| Positional parameters are accessible | Yes — Task 2 / 4 | None |
| `exec "$@"` actually starts command | No direct proof | Rebuild `lab07-parameters`, execute valid `echo` or `ls` |
| `ENV_MODE` branches execute | Not seen | Rebuild `lab07-modes` and capture three branch outputs |
| `start/stop/invalid` case statements execute | Not seen | Rebuild `lab07-commands`, capture output and exit status |
| Production hardening actually enabled | Not performed | Separate security test would be required |

**Training versus production:** This is a small educational entrypoint lab, not a deployed service or a claim of real production operational experience.

## Troubleshooting playbook

**Problem: `exec /entrypoint.sh: no such file or directory` even though the file exists.** Check script shebang and Linux line endings. Alpine has `/bin/sh`, but does not include `/bin/bash` by default. A CRLF shebang might refer to `/bin/sh\r` and fail. Repair line endings before building:

```bash
sed -i 's/\r$//' entrypoint.*.sh
```

**Problem: `permission denied`.** Ensure the file is executable *inside the image*. Each task's Containerfile includes `RUN chmod 755 /entrypoint.sh`.

**Problem: edited `entrypoint.sh`, output never changes.** The script is copied during `podman build`, not read live from the host at `podman run` time. Rebuild the relevant image, then run the correct tag:

```bash
podman build --no-cache -f Containerfile.modes -t lab07-modes .
podman run --rm -e ENV_MODE=production lab07-modes
```

**Problem: mode flag passed but no development/production banner.** Check `podman run -e ENV_MODE=development`, your script's variable name, the Containerfile's `COPY` source, and the image actually launched. `podman image inspect` confirms startup configuration, not the content of the script inside the image.

**Problem: `hello: not found`.** `exec "$@"` expects a real executable as `$1`; plain `hello world` is not a command. Use `echo hello world` or `ls -l /`.

**Problem: `invalid` exits nonzero.** That's a deliberate invalid-input response, not a container runtime failure. `podman run ... invalid; echo $?` can inspect the result.

## Practical application to Cloud / DevOps

Use argument and environment control for an image that may run a web server by default but can also perform one-off administrative tasks. Typical examples include a migration job, an initialization step before a web server, or a test worker. For **real services**, handle validation, exit codes, secrets, PID 1 signaling, read-only filesystems, and workload orchestration. See the [Deep Dive](DEEP-DIVE.md) before treating the educational examples as production-ready.

## Future evidence capture (optional)

1. Screen showing `lab07-parameters` valid command execution.
2. Screen with `lab07-modes` three distinct banners.
3. Screen with `lab07-commands` expected start, stop, and invalid exit status.

This would close the current validation gaps. Do not edit original screenshots to invent the missing states.

## Cleanup (optional)

```bash
podman rmi lab07-basic lab07-parameters lab07-modes lab07-commands
```

Avoid broad prune commands if your machine contains images for other labs.

---

**Maintainer:** Hafiz Mohammad Sunasara  
**Record classification:** Hands-on course journal with genuine screenshots and reproducible corrective examples  
**Next learning area:** More sophisticated startup validation, application health, signal handling, and image hardening
