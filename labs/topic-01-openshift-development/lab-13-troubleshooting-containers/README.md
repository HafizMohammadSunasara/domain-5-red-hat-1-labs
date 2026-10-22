# Lab 13 — Troubleshooting Containers

**Course:** Domain 5 → Linux and Open Source → Red Hat 1  
**Runtime:** Podman | **Workload:** Nginx on Alpine Linux  
**Status:** **Completed — self-reported by the learner**  
**Verification level:** Learner confirms all practical tasks were executed; original terminal outputs, screenshots, and an independent replay are **not** included in this repository. Examples below are *expected behavior*, not archived execution logs.

> **Quick path:** Follow this `README.md` as the complete practical runbook. For architecture, debugging methodology, logging internals, security and interview questions, read [DEEP-DIVE.md](DEEP-DIVE.md).

## 1. What this lab teaches

- Diagnose container startup/runtime issues with `podman logs` and `podman inspect`.
- Filter log output with **follow**, **time window**, and **last N lines**.
- Interpret container lifecycle state, process exit information, network settings, and runtime resource usage.
- Enter a running container with `podman exec` and inspect processes, configuration, and service connectivity.
- Distinguish an **empty log** from a **healthy service** and an **unavailable command** from a **broken application**.

### Prerequisites

- CLI basics and Podman installed (the course also mentions Docker, but the actual commands use Podman).
- Access to an RHEL/Fedora/CentOS or Debian/Ubuntu-based Linux environment, such as a VM.
- Registry access to fetch `nginx:alpine`.
- Local port `8080` available, or choose a different host port with care.

**Command context legend:** `HOST$` means your Linux/VM shell; `CONTAINER$` means the shell opened with `podman exec`; commands shown in SQL or other tools are not relevant here. Run the OS-specific installer **only if needed**, not both.

---

## 2. Lab Setup — ALL instructor steps

### Setup 1 — Install Podman if it is not already installed

On **RHEL/CentOS/Fedora**:

```bash
sudo dnf install -y podman  # For RHEL/CentOS/Fedora
```

On **Debian/Ubuntu** instead:

```bash
sudo apt-get install -y podman  # For Debian/Ubuntu
```

Verify your available installation:

```bash
podman --version
```

> Instructor lists both installation alternatives. They are **not** meant to be executed on the same operating system. If Podman already works, installation can be skipped.

### Setup 2 — Pull the Nginx Alpine image

```bash
podman pull docker.io/library/nginx:alpine
```

The fully qualified image reference avoids ambiguity about which registry is used.

### Setup 3 — Run a test container

**Original instructor command:**

```bash
podman run -d --name nginx-test -p 8080:80 nginx:alpine
```

- `-d`: run detached, with Nginx in the container's foreground.
- `--name nginx-test`: human-readable container identifier.
- `-p 8080:80`: forward host port 8080 to container port 80; by default this may bind **all host interfaces**.
- `nginx:alpine`: run a lightweight Nginx image. Podman may resolve the short image name differently depending on short-name configuration.

**Safer alternative for a fresh local-only lab** (use instead of, **not in addition to**, the command above):

```bash
podman run -d --name nginx-test -p 127.0.0.1:8080:80 docker.io/library/nginx:alpine
```

This restricts published access to the VM's local interface. If `nginx-test` already exists, do not blindly launch a duplicate: inspect the existing container first.

**Useful sanity checks (supplemental):**

```bash
podman ps --filter name=nginx-test
curl -I http://127.0.0.1:8080
```

A successful local HTTP request should be reflected in Nginx access logs. `curl` on the **host** may need installation; `wget` can be used if available. If running Podman inside a VM, `127.0.0.1` above means *the VM*, not the Windows host.

---

## 3. Task 1 — View Container Logs with Filters

### Subtask 1.1 — View basic logs

**Instructor command 1: basic logs**

```bash
podman logs nginx-test
```

**Expected behavior:** Nginx stdout/stderr logs are shown, to the extent any entries have been emitted. Access logs generally appear **after requests**; startup messages or errors can appear before requests. Do not mistake an empty access log for a failed container.

**Instructor command 2: follow logs in real time**

```bash
podman logs -f nginx-test
```

- `-f` follows new log entries.
- In another host terminal, generate traffic if nothing appears:

```bash
curl http://127.0.0.1:8080
```

- Return to the log terminal and press **Ctrl+C** to stop following. This interrupts the *logs viewer*; it does **not** stop the Nginx container.

### Subtask 1.2 — Filter logs by time

**Instructor command 1: last five minutes**

```bash
podman logs --since 5m nginx-test
```

**Expected:** Entries whose timestamps fall inside the recent time window, if the container has emitted any.

**Instructor command 2: last ten lines**

```bash
podman logs --tail 10 nginx-test
```

**Expected:** Up to ten most recent logged lines. If fewer exist, fewer may print.

**Additional useful experiment (not an instructor requirement):**

```bash
podman logs --since 5m --tail 10 nginx-test
```

### Task 1 troubleshooting

Instructor's note: if logs are empty, check whether the container runs:

```bash
podman ps
```

Also useful: generate a fresh request, check stderr output, and inspect the exit state rather than assuming a blank log means an application failure.

---

## 4. Task 2 — Inspect Container State

### Subtask 2.1 — Check container status

**Instructor command 1: list running containers**

```bash
podman ps
```

**Expected:** `nginx-test` appears if still running. Exited containers are excluded by default; for those, use `podman ps -a`.

**Instructor command 2: full inspection**

```bash
podman inspect nginx-test
```

Explore these fields in the returned JSON (layout varies by Podman version):

| Area | What to look for | Engineering meaning |
| --- | --- | --- |
| `State` | `Status`, `Running`, `ExitCode`, `Error`, times | Is the container still alive? If not, why might it have exited? |
| `Config` | Environment, image configuration, `Entrypoint`, `Cmd` | What process and configuration were intended to start? |
| `NetworkSettings` | Assigned IP, networks, port configuration | Where can the container be reached? |
| `HostConfig` / `Mounts` / port-related fields | Host port mapping, mounts and security settings | How is the container connected to the host? |

**Supplemental focused inspection** (easier to reason about than a long JSON document):

```bash
podman inspect --format '{{.State.Status}}' nginx-test
podman inspect --format '{{.State.ExitCode}}' nginx-test
podman port nginx-test
```

Note: `State.Status` is commonly `running` (lowercase), while `State.Running` is a boolean. A live container's `ExitCode` does not describe a completed execution. Avoid copying complete `inspect` output into a public repo if it includes credentials, private IPs or confidential environment variables.

### Subtask 2.2 — Check resource usage

**Instructor command:**

```bash
podman stats nginx-test
```

**Expected:** Continuously updating resource information, commonly including CPU usage, memory, network I/O and other available metrics. Fields depend on Podman version and cgroup configuration.

Press **Ctrl+C** to exit the live stats viewer without terminating the container.

**Supplemental one-shot alternative:**

```bash
podman stats --no-stream nginx-test
```

### Task 2 troubleshooting

Instructor note: if a container is stuck, `podman stop` followed by restart may help. **First collect logs and inspect state**, because a restart can destroy diagnostic evidence. A controlled restart of this named disposable test container, if necessary:

```bash
podman stop nginx-test
podman start nginx-test
```

If the process immediately exits again, inspect `podman logs nginx-test` and `podman ps -a` before trying more restarts.

---

## 5. Task 3 — Use `exec` to Debug Inside Container

### Subtask 3.1 — Enter the container shell

**Instructor command 1: interactive shell** (from the host):

```bash
podman exec -it nginx-test /bin/sh
```

Once inside the container, the prompt is now **inside Alpine Linux**; host commands such as `podman ...` should normally be run in the **host** terminal, not this shell.

**Instructor command 2: inspect running processes** (inside container):

```bash
ps aux
```

**Expected:** If supported by the image's process utilities, a process list including Nginx master/worker processes and the interactive shell. Alpine commonly uses BusyBox utilities, and `ps aux` support/output can differ from full `procps` implementations.

**If `ps aux` is unavailable or behaves differently:**

```sh
ps
cat /proc/1/cmdline
```

The `/proc/1/cmdline` output is NUL-separated; it may display without human-friendly line breaks. These commands are extra diagnostic alternatives, not replacements silently inserted into the instructor's task.

### Subtask 3.2 — Debug service issues

**Instructor command 1: read Nginx configuration** (inside container):

```bash
cat /etc/nginx/nginx.conf
```

**Expected:** Config file contents; identify the `events`/`http` blocks, include directives and Nginx logging configuration.

**Instructor command 2: check local connectivity** (inside container):

```bash
curl localhost
```

**Important image caveat:** `nginx:alpine` **may not include `curl`**. A `curl: not found` error indicates a missing debugging utility, not necessarily a dead Nginx service. Try the image's BusyBox `wget` if available:

```sh
wget -qO- http://127.0.0.1/
```

If the container has neither HTTP client, leave the container shell (`exit`) and test from the host:

```bash
curl http://127.0.0.1:8080
```

**Additional service-specific validation** (inside container):

```sh
nginx -t
```

This checks configuration syntax; it does not alone prove that the service is reachable or serving the expected site.

Finish the interactive shell:

```sh
exit
```

**Instructor troubleshooting note:** If `/bin/sh` fails, `/bin/bash` might work *only if Bash is installed*. For `nginx:alpine`, `/bin/sh` is the normal choice; Bash is not usually present in minimal Alpine images. Check the chosen image before assuming otherwise.

---

## 6. Complete instructor command checklist

| Stage | Instructor command / operation | Included |
| --- | --- | --- |
| Setup | `sudo dnf install -y podman` — RHEL family option | ✓ |
| Setup | `sudo apt-get install -y podman` — Debian family option | ✓ |
| Setup | `podman pull docker.io/library/nginx:alpine` | ✓ |
| Setup | `podman run -d --name nginx-test -p 8080:80 nginx:alpine` | ✓ |
| 1.1 | `podman logs nginx-test` | ✓ |
| 1.1 | `podman logs -f nginx-test` and Ctrl+C | ✓ |
| 1.2 | `podman logs --since 5m nginx-test` | ✓ |
| 1.2 | `podman logs --tail 10 nginx-test` | ✓ |
| Tip | `podman ps` for empty logs | ✓ |
| 2.1 | `podman ps` | ✓ |
| 2.1 | `podman inspect nginx-test` | ✓ |
| 2.2 | `podman stats nginx-test` | ✓ |
| Tip | `podman stop` and restart guidance | ✓ |
| 3.1 | `podman exec -it nginx-test /bin/sh` | ✓ |
| 3.1 | `ps aux` | ✓ |
| 3.2 | `cat /etc/nginx/nginx.conf` | ✓ |
| 3.2 | `curl localhost` | ✓ |
| Tip | `/bin/bash` fallback note | ✓ |
| Next step | `podman system df` | ✓ |
| Cleanup | `podman stop nginx-test` | ✓ |
| Cleanup | `podman rm nginx-test` | ✓ |

The checklist preserves the instructor commands as given. Supplemental corrections or safer alternatives are explicitly labeled throughout this document.

---

## 7. Troubleshooting scenarios — quick decision guide

| Symptom | Likely causes to investigate | First checks |
| --- | --- | --- |
| `nginx-test` missing in `podman ps` | Exited / never created / wrong name | `podman ps -a`, `podman logs nginx-test` |
| Port 8080 already in use | Another local service or container | `ss -ltnp` or `podman ps`, then choose a free host port |
| No Nginx access log | No requests, log destination differs, time filter too narrow | Generate request; `podman logs nginx-test` |
| `podman logs --since 5m` empty | Nothing logged in last five minutes | Generate fresh request; compare unfiltered logs |
| `curl: not found` inside container | Minimal image lacks curl | Try BusyBox `wget` or host curl |
| `ps aux` fails | BusyBox option differences or process tools absent | Try `ps`, `/proc/1/cmdline` |
| `podman exec` fails | Container exited; missing executable; permissions | `podman ps -a`, image's shell availability |
| HTTP connection refused | Nginx stopped, bad host/port mapping, incorrect network namespace | `podman ps`, `podman port`, `podman logs` |
| `podman stats` limited or errors | Cgroup/rootless/runtime constraints | Inspect Podman version/cgroup availability; use available metrics |
| Nginx syntax invalid | Broken config or included file | `nginx -t`, full error log |

Never publish credentials, bearer tokens or full sensitive environment listings when sharing diagnostic artifacts.

---

## 8. Conclusion, practice extensions and cleanup

### Instructor's three lab objectives — completed (learner-reported)

- [x] Viewed and filtered Nginx container logs.
- [x] Inspected container status, configuration/network state, and resource usage.
- [x] Used `exec` to debug processes, Nginx configuration, and HTTP connectivity.

### Next steps from the instructor

1. Practice a **deliberately misconfigured** disposable container (for example, invalid Nginx configuration). Predict the symptom, collect logs, inspect state, isolate the cause and fix it. Do **not** deliberately break an important running service.
2. Explore disk usage by images/containers/volumes:

```bash
podman system df
```

### Exact cleanup commands from the instructor

Run in your **host** terminal when finished with this disposable lab container:

```bash
podman stop nginx-test
podman rm nginx-test
```

Cleanup only removes this named test container; it does not remove the image or wipe unrelated containers.

### Lab feedback and reflection prompts

- **Difficulty:** Easy / Medium / Hard — choose from your own experience; not guessed here.
- **Challenges faced:** Describe real encountered errors, if any. No incidents are fabricated.
- **What mattered most:** logs show application behavior, inspect shows runtime configuration/state, stats shows resource activity, and exec reveals the container's internal environment.

### Proof-of-work and evidence integrity

- **Confirmed by learner:** all tasks of Lab 13 executed successfully.
- **Not independently verified here:** precise timestamps, observed log lines, cgroup stats values, screenshots and error-recovery transcripts.
- **Recommended authentic evidence:** (1) logs with an actual request and filtered output; (2) `inspect` and live `stats` (redact sensitive information); (3) shell showing Nginx config/processes and a successful HTTP check. Add only if genuinely captured.
- For the repository-wide integrity policy, see [Engineering Proof of Work](../../evidence/PROOF-OF-WORK.md).

**Continue:** [Technical Deep Dive](DEEP-DIVE.md) · [All Red Hat 1 Labs](../LABS-INDEX.md).
