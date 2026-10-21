# Lab 13 — Deep Dive: Container Troubleshooting with Podman

**Domain 5 → Linux and Open Source → Red Hat 1**  
**Lab:** Troubleshooting Containers | **Case study:** `nginx:alpine` | **Status:** Completed — self-reported  
**Companion:** [Full practical lab runbook](README.md)

> This document is a technical explanation and reusable diagnostic playbook. Commands and sample interpretations are not presented as preserved terminal output from the author's lab. The learner reports having completed Lab 13; original logs, screenshots and independent replay have not been provided here.

## 1. The real engineering problem

A container can be created successfully but still fail to deliver a usable application. For example:

- The image pulled correctly, but the process exits immediately.
- Nginx runs, but clients receive `connection refused` because of a port mismatch.
- The service listens and returns HTTP 200, but an expected route is missing.
- No recent log entry exists even though the container is healthy.
- `podman exec` cannot run because the container is stopped—or because the utility is absent from a minimal image.
- CPU or memory spikes while the service is still running.

**Being `running` is not the same as being `ready` or `correct`.** A reliable engineer checks the application's observed behavior and works backward to identify the cause.

The fundamental debugging loop:

```text
User-visible symptom
        |
        v
1. Reproduce the problem
        |
        v
2. Collect evidence (logs + state + stats + network)
        |
        v
3. Form a hypothesis
        |
        v
4. Run the smallest safe diagnostic test
        |
        v
5. Fix / validate / document
```

Avoid random restarts or unexplained privilege changes. They may erase useful evidence or obscure the real cause.

## 2. Mental model: the three observation planes

| Observation plane | Key Podman command | What it can establish | What it cannot establish on its own |
| --- | --- | --- | --- |
| **Application output** | `podman logs` | What the container's main process wrote to stdout/stderr | Whether a quiet service is definitely unhealthy |
| **Runtime state/config** | `podman ps`, `podman inspect` | Running/exited state, process settings, ports, mounts, metadata | Whether HTTP requests produce correct business results |
| **Inside the container** | `podman exec` | Visible files, processes, config and local HTTP checks | Whether host routing/firewall/external clients are correct |
| **Resource telemetry** | `podman stats` | Available CPU/memory/I/O metrics | Full root-cause explanation without correlating other evidence |

These viewpoints complement each other. The goal is to **correlate** signals rather than trust a single successful command.

## 3. Setup, namespaces and why the host can reach Nginx

Instructor environment:

```bash
podman pull docker.io/library/nginx:alpine
podman run -d --name nginx-test -p 8080:80 nginx:alpine
```

Conceptual path of a request:

```text
Linux host / RHEL VM
    curl http://127.0.0.1:8080
             |
             v
    host port 8080
             |
        Podman networking
             |
             v
    nginx-test network namespace
    container port 80
             |
             v
    Nginx worker handles HTTP request
             |
             v
    HTTP response + access-log entry
```

Key distinctions:

- **Container port 80:** Nginx's configured listen port inside its network namespace.
- **Host port 8080:** The endpoint exposed from the VM to clients subject to binding/firewall/network arrangements.
- **`-p 8080:80`:** Typically listens on host interfaces rather than automatically limiting exposure to loopback; check with `podman port` and host socket tools.
- **`-p 127.0.0.1:8080:80`:** A more limited binding for local debugging. Inside a VM, this is the VM's localhost.
- **The image tag is not a container instance:** `nginx:alpine` is a reusable image; `nginx-test` is a particular container created from it.

### Detached mode is not a guarantee of uptime

The `-d` flag detaches the CLI, not the underlying process from its lifecycle. A container ends when its main process terminates. The Nginx image is configured to keep Nginx in the foreground. If configuration is invalid or the process exits, detaching will not keep it alive.

## 4. Logs: what they really represent

Runbook commands:

```bash
podman logs nginx-test
podman logs -f nginx-test
podman logs --since 5m nginx-test
podman logs --tail 10 nginx-test
```

### Source and transport

Most OCI container runtimes collect text written to the container process's standard output (`stdout`) and standard error (`stderr`) using their configured logging mechanisms. In the official Nginx container image, logging is commonly arranged so access and error messages can reach these streams. However, logging configuration and runtime drivers can vary.

An Nginx **access log** generally requires a request. If you have not generated any traffic, `podman logs` may show startup output, warning messages, or no access lines.

### Four subtly different queries

| Command | Question it answers |
| --- | --- |
| `podman logs nginx-test` | What has the log collector retained for this container? |
| `podman logs -f nginx-test` | What is being emitted **from now on** (while showing available retained logs)? |
| `podman logs --since 5m nginx-test` | What entries have timestamps in the recent five-minute window? |
| `podman logs --tail 10 nginx-test` | What are the last **up to** ten log lines? |

`--since` is a time filter; `--tail` is a count filter. A quiet service can produce an empty time-filtered result without a fault. A busy service's last 10 log lines may be too narrow to include the initial root cause, so broaden the view when diagnosing startup problems.

### Minimal validation experiment

On the host:

```bash
curl -I http://127.0.0.1:8080
podman logs --tail 10 nginx-test
```

A newly generated HTTP request should usually produce an Nginx access entry if access logging is enabled to a collected destination. If not, investigate Nginx's log configuration and the container's runtime logs before assuming Podman is malfunctioning.

### What `-f` and Ctrl+C actually do

`podman logs -f` is a client process that watches the stream. Pressing **Ctrl+C** stops the watcher; it does not signal the Nginx PID 1 in the same way as `podman stop`.

### Security and reliability considerations

- Never place passwords, API tokens or secrets in application logs.
- Establish retention and log rotation for long-running deployments; logs can consume host storage.
- Correlate log timestamps with timezone and request timing; do not fabricate chronology from expected examples.
- Search for the **first causally relevant failure**, not just the last error after a cascade.

## 5. Inspecting runtime state and image configuration

Instructor commands:

```bash
podman ps
podman inspect nginx-test
```

### `podman ps` vs `podman ps -a`

- `podman ps` shows **running** containers.
- `podman ps -a` includes stopped and exited containers, making it valuable for startup failures.

A container missing from `podman ps` is **not** proof it was deleted. It may have exited. Confirm with `podman ps -a`.

### Inspect data: asking better questions

| Inspect area | Diagnostic question |
| --- | --- |
| `.State.Status` | `running`, `exited`, or another state? |
| `.State.Running` | Is the runtime reporting an active container? |
| `.State.ExitCode` | If exited, what numeric exit status was recorded? |
| `.State.Error` | Did the runtime record an error? |
| `.Config.Entrypoint`, `.Config.Cmd` | What was configured to start inside the container? |
| `.Config.Env` | What configuration/environment was supplied? (Sensitive: do not publish indiscriminately.) |
| Networking / port fields | Does a port map exist; which host bind/IP was selected? |
| Mounts | Are host paths or volumes mounted where expected? |

Useful targeted commands:

```bash
podman inspect --format '{{.State.Status}}' nginx-test
podman inspect --format '{{.State.ExitCode}}' nginx-test
podman port nginx-test
```

### Exit codes: don't oversimplify

A nonzero exit code often means the process failed, but interpreting it requires logs and context. There is no universal mapping from exit code to precise root cause: the application may choose its own statuses, and a process killed by a signal can also report a special exit result. In particular, **an exit code without logs or state history is not a diagnosis.**

### Health checks vs basic liveness

`running` means an OS process is still alive. It does not necessarily mean Nginx's routes serve expected content or the app is ready for traffic. A deliberate HTTP test is more meaningful for service behavior, and production deployments often add health/readiness checks tailored to their applications.

## 6. Resource monitoring with `podman stats`

The instructor runs:

```bash
podman stats nginx-test
```

Press **Ctrl+C** after observing the live view.

Possible metrics vary with Podman version, platform and cgroup/rootless setup:

- CPU usage: approximate amount of compute used by the workload in the sampling interval.
- Memory: usage relative to the container's accounting/limits, when available.
- Network I/O: traffic movement, but not a substitute for tracing connectivity or measuring latency.
- Block I/O: read/write activity when the runtime can observe it.
- Process count: where reported.

**Do not equate a high CPU reading with a defect automatically.** It may represent expected workload. Similarly, low CPU on a failing service can simply mean it is not receiving traffic.

For a snapshot instead of a continuously updating stream:

```bash
podman stats --no-stream nginx-test
```

If stats are missing or an option is unavailable, check Podman version and resource-controller support. Avoid claiming precise metrics that were never retained.

## 7. Entering a container: `exec` is a debugging tool, not a repair strategy

Instructor commands:

```bash
podman exec -it nginx-test /bin/sh
ps aux
cat /etc/nginx/nginx.conf
curl localhost
```

### What `podman exec -it` does

- `exec`: starts an **additional process** in an existing running container.
- `-i`: keeps standard input connected.
- `-t`: allocates a pseudo-terminal for an interactive shell.
- `/bin/sh`: shell executable appropriate for Alpine-based minimal images.

The shell normally runs as a *new process*. It does not replace the Nginx process, and closing the shell ordinarily does not stop Nginx.

### Why minimal images surprise engineers

Minimal images deliberately omit many diagnostic tools to reduce size and dependencies. A missing tool indicates the **image lacks the utility**, not necessarily the service is broken.

Possible examples:

```sh
ps aux             # exact instructor instruction; BusyBox support may vary
ps                 # common smaller fallback
cat /proc/1/cmdline
curl localhost     # may fail: curl not installed
wget -qO- http://127.0.0.1/   # common BusyBox fallback
nginx -t           # Nginx configuration syntax check
```

Inside the container, `localhost` resolves to the **container's** network namespace. On the host, `localhost:8080` refers to the **host** port forwarded to container port 80. Confusing these two views causes many apparent connectivity mysteries.

### Nginx config investigation

`cat /etc/nginx/nginx.conf` shows the main configuration file. Production configurations frequently include files from additional directories. Follow `include` directives, inspect listen/root/log directives and use `nginx -t` to validate syntax. Successful syntax validation alone cannot prove the intended virtual host or response content is correct.

### Shell fallback

The lab suggests `/bin/bash` if `/bin/sh` fails. On Alpine, however, `/bin/sh` is the expected shell and Bash is usually absent. The general rule is to use a shell that actually exists in the image, not to assume every Linux image contains Bash.

## 8. Diagnose by layer: three representative scenarios

These are **hypothetical exercises**, not claims about errors encountered while completing Lab 13.

### Scenario A — “The container is not in `podman ps`”

1. Run `podman ps -a --filter name=nginx-test` to distinguish exited from never-created.
2. Read `podman logs nginx-test` for startup errors.
3. Inspect `.State.Status`, `.State.ExitCode` and `.State.Error`.
4. If logs point to configuration, inspect config and test syntax in an appropriate controlled environment.
5. Make the minimal correction and verify a successful HTTP response.

**Avoid:** repeatedly restarting without reading the first failure.

### Scenario B — “HTTP does not work, but container is running”

1. Check `podman ps` to confirm the container instance is active.
2. Check host port mapping with `podman port nginx-test`.
3. From the VM, request `http://127.0.0.1:8080`.
4. Inside the container, request `http://127.0.0.1/` with a tool actually installed.
5. Compare the two perspectives: internal request works but host request fails → look at network publishing, host firewall, interfaces, and VM-to-host networking.

**Avoid:** assuming an Nginx error solely because Windows cannot contact a service that is only listening on the VM's localhost.

### Scenario C — “`curl localhost` prints command not found”

1. Confirm the image is based on Alpine/uses a minimal userspace.
2. Use `command -v curl` (and `command -v wget`) to check available clients.
3. Try BusyBox `wget -qO- http://127.0.0.1/`.
4. If needed, test through the host's published port.
5. Distinguish **missing diagnostic binary** from **HTTP failure** in your incident notes.

**Avoid:** modifying a production container on the fly merely to add debugging packages; prefer a controlled or purpose-built debug environment.

## 9. Safe, repeatable troubleshooting playbook

A compact run sequence for this specific lab (run on the **host**, unless noted):

```bash
# Identify the container and whether it exited
podman ps -a --filter name=nginx-test

# Observe retained application logs
podman logs --tail 50 nginx-test

# Read precise state and ports
podman inspect --format '{{.State.Status}}' nginx-test
podman inspect --format '{{.State.ExitCode}}' nginx-test
podman port nginx-test

# Collect a one-shot resource view when supported and running
podman stats --no-stream nginx-test

# Prove service behavior from the VM host
curl -I http://127.0.0.1:8080

# Validate Nginx configuration when the container is running
podman exec nginx-test nginx -t
```

Record the command, its **actual observed result**, a concise interpretation and the next hypothesis. Do not paste fake examples into the repository as if they were captured during your session.

### Example incident-note template (unfilled)

```text
Observed symptom: <describe exactly>
Environment: <OS, Podman version, image tag>
Reproduction: <command + real result>
Evidence: <relevant sanitized log/inspect output>
Hypothesis: <what likely explains the result>
Test: <safe command that supports/refutes hypothesis>
Change: <what was modified, if anything>
Verification: <real observed HTTP/status result>
Follow-up: <preventive improvement>
```

## 10. Production and security implications

- **Keep ports scoped:** for a purely local lab, bind published ports to `127.0.0.1` rather than exposing unnecessary services on all host interfaces.
- **Least privilege:** do not use privileged containers or root escalation as a first-choice fix.
- **Logs can contain sensitive data:** redact secrets and personal details before uploading evidence.
- **Inspect can reveal configuration secrets:** prefer targeted/redacted views in public GitHub repositories.
- **Minimal images are expected:** do not assume utilities like Bash, `curl`, `netstat` or full `ps` exist.
- **Observability is layered:** logs, lifecycle state, metrics, network checks and application-level health each answer different questions.
- **Reproducibility matters:** record image tags and Podman/host context; floating image tags can change over time.
- **Evidence before restart:** retain the first useful error message and state, then change one thing at a time.
- **Cleanup with scope:** stop/remove only the disposable `nginx-test` container after confirming it is safe to remove.

## 11. Interview-style questions with answers

**Q1. Why might `podman logs nginx-test` be empty while Nginx works?**  
An access log is generated only when requests occur and logging is configured accordingly. No traffic, filtering, or a different log destination can lead to little or no visible output.

**Q2. What's the difference between `podman ps` and `podman inspect`?**  
`ps` is a concise runtime inventory; `inspect` provides detailed runtime and configuration metadata for a specific resource.

**Q3. Why would a detached container exit immediately?**  
Detached mode does not keep its main process alive. If the command finishes or crashes, the container normally exits.

**Q4. What do `--since 5m` and `--tail 10` actually filter?**  
The first filters by relative time; the second selects the last up to ten log lines. They answer different questions.

**Q5. Does `podman logs -f` stop the container on Ctrl+C?**  
No. Ctrl+C stops the log-streaming client, not the detached container's Nginx process.

**Q6. Why may `curl localhost` fail inside `nginx:alpine`?**  
The image may not contain curl. Check installed utilities, try a supported HTTP tool such as BusyBox wget, or test from the host.

**Q7. What does `podman exec -it` require?**  
An existing *running* container and an executable available inside it. `-i` enables interactive input, and `-t` allocates a terminal.

**Q8. If HTTP works from inside the container but fails from the host, where do you investigate?**  
Port mapping, listening interfaces, host/VM network namespace, firewall, and the target host port. Do not immediately blame the application.

**Q9. Can `nginx -t` confirm the application is healthy?**  
It validates Nginx configuration syntax, which is valuable but insufficient. Also exercise the intended HTTP route and inspect application behavior.

**Q10. What can `podman stats` tell you that logs cannot?**  
Resource behavior such as available CPU, memory and I/O metrics. The measurements can narrow hypotheses but do not prove a root cause on their own.

**Q11. What is the value of checking `/proc/1/cmdline`?**  
It can help reveal PID 1's executable/arguments when richer process-listing tools are unavailable. It does not replace application logs or inspect metadata.

**Q12. Which debug evidence is safe to commit publicly?**  
Redacted logs, commands, configuration excerpts, code, and real screenshots that do not leak secrets, customer information, or credentials. Never mislabel expected output as an observed result.

## 12. Complete lab objectives, next steps and proof of work

### Instructor coverage

| Original lab area | Deep-dive coverage |
| --- | --- |
| Setup: Podman install, image pull, Nginx run | Sections 3 and linked practical runbook |
| Task 1: basic/follow/time/tail logs | Section 4 |
| Task 2: `ps`, `inspect`, `stats` | Sections 5–6 |
| Task 3: shell, processes, config, HTTP connectivity | Section 7 |
| Troubleshooting: empty logs, stop/restart, shell availability | Sections 4, 7–9 |
| Next steps: broken container and `podman system df` | Below |
| Cleanup: stop/remove the test container | Below |
| Checklist and feedback | Below |

### Suggested extension 1 — intentionally broken disposable workload

Recreate a controlled instance using a broken Nginx config in a separate test environment, predict failure, then use `podman logs`, `podman ps -a` and `podman inspect` to identify the difference. Avoid introducing faults into systems containing real data or serving other users.

### Suggested extension 2 — container disk accounting

```bash
podman system df
```

This reports approximate disk consumption for Podman-managed images, containers and volumes. It does not directly explain every host disk-use issue.

### Original cleanup

```bash
podman stop nginx-test
podman rm nginx-test
```

### Lab completion checklist — learner confirmation

- [x] Viewed Nginx container logs using basic/follow/time/tail filters.
- [x] Inspected container state and resource usage.
- [x] Debugged a running Nginx container using an interactive shell, process/config inspection, and HTTP checks.

**User-reported completion:** Yes.  
**Published original command transcript:** Not supplied.  
**Published screenshot/evidence files:** Not supplied.  
**Difficulty feedback:** Not yet provided; do not guess Easy/Medium/Hard.  
**Challenges personally encountered:** Not specified; the scenarios in this document are teaching examples, not reports of incidents that definitely occurred.

See also the repository's [Engineering Proof of Work](../../evidence/PROOF-OF-WORK.md) guidance.

---

**Primary practical reference:** [Lab 13 README — Every instructor task and command](README.md)  
**Course navigation:** [Red Hat 1 Labs Index](../LABS-INDEX.md)
