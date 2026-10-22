# Lab 09 — Deep Dive: ENTRYPOINT, CMD, PID 1 and Container Startup

**Track:** Domain 5 → Linux and Open Source → Red Hat 1  
**Audience:** Learners, future self-revision, and engineers reviewing technical reasoning  
**Companion:** [Practical Lab Guide](README.md)  
**Evidence note:** Technical explanations and example outputs are educational and **not** retained records from an independently verified lab execution.

## 1. The engineering problem this lab solves

A container image contains software, but **what runs when someone starts a container from it?** An image might contain Python, Nginx, shell scripts and command-line tools. It needs a default startup behavior so the operator doesn't have to type a complete command every time.

`ENTRYPOINT` and `CMD` specify that behavior. In exec form, think of them as:

> **ENTRYPOINT = the program (and possibly fixed arguments); CMD = default additional arguments.**

This is a mental model for the common **exec-form ENTRYPOINT + exec-form CMD** combination. If there is no `ENTRYPOINT`, `CMD` can specify the whole default command. Shell-form rules differ.

### Small example

```dockerfile
ENTRYPOINT ["python3"]
CMD ["app.py"]
```

Running `podman run myimage` starts `python3 app.py` **if** Python and `app.py` are present in that image. Running `podman run myimage test.py` starts `python3 test.py`; `test.py` must also exist. You have changed the runtime arguments without rebuilding the image.

## 2. Inside Task 1: building a startup command

The lab uses:

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal
ENTRYPOINT ["echo", "Entrypoint says:"]
CMD ["Default CMD message"]
```

`FROM` provides a Red Hat UBI 9 Minimal filesystem and runtime environment. It does **not** mean your host operating system must be RHEL 9; the host provides the compatible Linux container runtime/kernel.

When Podman starts a container, the effective executable and argument list for this example are conceptually:

```text
argv[0] = echo
argv[1] = Entrypoint says:
argv[2] = Default CMD message
```

`echo` joins its operands with spaces and prints a newline, producing the **expected** output:

```text
Entrypoint says: Default CMD message
```

A common misconception is that `CMD` is a second command executed *after* `ENTRYPOINT`. It is **not**: here it supplies arguments to the ENTRYPOINT.

## 3. How runtime overrides work — four cases

| Scenario | Run instruction | What starts |
| --- | --- | --- |
| Image defaults | `podman run --rm entrypoint-demo` | `echo "Entrypoint says:" "Default CMD message"` |
| Replace CMD arguments | `podman run --rm entrypoint-demo "Custom message"` | `echo "Entrypoint says:" "Custom message"` |
| Script with defaults | `podman run --rm greet-demo` | `greet.sh "OpenShift Lab" "Red Hat"` |
| Replace executable | `podman run --rm --entrypoint echo greet-demo "Hello"` | `echo "Hello"` |

**Rule:** For the exec-form examples in this lab, arguments after an image name replace the default `CMD`, while `--entrypoint` changes the executable. Neither operation rebuilds the image or modifies its Dockerfile.

## 4. Why the shell script is a significant step

The lab's script is:

```sh
#!/bin/sh
echo "Welcome to $1 from $2"
```

This moves us from a fixed Linux command to a **custom application entrypoint**.

- `#!/bin/sh` chooses the POSIX shell to interpret the script.
- `$1` is the first positional argument, and `$2` is the second.
- `COPY greet.sh /usr/local/bin/` packages the script in the image.
- `chmod +x greet.sh` sets the executable bit before packaging.
- `ENTRYPOINT ["/usr/local/bin/greet.sh"]` selects it as the startup script.
- `CMD ["OpenShift Lab", "Red Hat"]` supplies two default arguments.

With defaults, the script prints `Welcome to OpenShift Lab from Red Hat`. When supplied with `"Container Workshop" "Instructor"`, the script prints a different greeting. The same image supports multiple input values.

### Why quotations matter

`"OpenShift Lab"` is a **single** argument even though it contains a space. Remove the quotes in an interactive shell and the script may receive a different number of arguments, changing `$1` and `$2`.

## 5. Connection to Linux processes and container lifetime

You already learned that `-d` only detaches from the terminal. A container normally stops after its main process exits.

In this lab the default executable is `echo`, or a script that runs `echo` and finishes. So the container exits quickly **by design**. This is not a Podman crash.

In contrast, a foreground web server such as Nginx or a Python API server keeps running while its main process remains alive, assuming it is healthy and not terminated.

### PID 1 and shutdown signals

A container has a process with PID 1 in its process namespace. The startup process (or an init wrapper when configured) is central to graceful shutdown and process reaping. Container runtimes typically send termination signals during stop operations, and well-designed applications handle those signals.

Exec-form startup avoids automatically inserting an intermediate `/bin/sh -c` for an ordinary command, which usually simplifies signal delivery. **Exec-form alone does not guarantee correct signals**: your application and any wrappers still need to handle them.

### Startup script for a real long-running service

A *different* script pattern—not the exercise's `greet.sh`—could look like:

```sh
#!/bin/sh
set -eu
echo "Preparing application startup..."
exec "$@"
```

`exec "$@"` replaces the wrapper shell with the intended application, helping that application receive signals directly. The image's CMD might then provide the server command and arguments. Do not use this generic wrapper unless the actual image, application command and security behavior are reviewed.

## 6. Exec form vs shell form — what's genuinely different?

### Exec form

```dockerfile
ENTRYPOINT ["echo", "Entrypoint says:"]
CMD ["Default CMD message"]
```

An explicit JSON array passes argument boundaries as defined. Variables such as `$HOME` are **not automatically expanded by a shell** in pure exec form; if you need shell expansion, explicitly run a shell or have the application handle it.

### Shell form

```dockerfile
ENTRYPOINT echo "Shell form ENTRYPOINT:"
CMD echo "Shell form CMD"
```

Shell form typically executes through `/bin/sh -c` on Linux images. Crucially, **shell-form ENTRYPOINT generally ignores CMD and runtime command arguments** rather than running CMD as a second standalone command. In this lab, the expected output is only `Shell form ENTRYPOINT:`.

Shell form can be useful when shell features are actually required, such as pipes or expansion, but it has different quoting and signal-handling implications. For long-running services, prefer an appropriate exec-form startup.

## 7. How to diagnose a startup problem

Think like an engineer, not a command memorizer:

1. **What image was used?** Check the tag and base image.
2. **What is configured to run?** Inspect `Config.Entrypoint` and `Config.Cmd`.
3. **Were runtime arguments supplied?** They may replace defaults.
4. **Is the executable inside the image?** Minimal base images don't contain every tool.
5. **Is the script executable and LF-formatted?** Check executable bit, shebang and line endings.
6. **Does the process exit immediately by design?** `echo` will; long-running services differ.
7. **What do logs and exit status show?** Run diagnostic commands instead of guessing.

Useful starting points:

```bash
podman image inspect greet-demo --format '{{json .Config.Entrypoint}} {{json .Config.Cmd}}'
podman ps -a
podman logs CONTAINER_NAME_OR_ID
podman inspect CONTAINER_NAME_OR_ID --format '{{.State.ExitCode}}'
```

Use actual container identifiers for the last two commands. The `--rm` examples remove exited containers automatically, so there may be no container left to inspect afterward.

### Common faults

| Symptom | Likely explanation |
| --- | --- |
| `permission denied` launching script | Executable bit missing; copy permissions or runtime security also worth checking |
| Script appears present but cannot execute | CRLF shebang, wrong interpreter path, or missing interpreter |
| Unexpected printed words | CMD replacement, incorrect shell quoting, or stale image tag |
| Container instantly exits | Its command has finished, which may be expected |
| Can't `exec` into container | Container isn't running; `exec` requires a running target |

## 8. Real-world application patterns

### A. Web servers

An Nginx image commonly starts a foreground Nginx process. The process must stay in the foreground for normal container lifecycle tracking.

### B. Python applications

```dockerfile
ENTRYPOINT ["python3"]
CMD ["server.py"]
```

This separates the interpreter from the default script. It assumes the script and Python interpreter exist in the image. Production configurations might instead use a dedicated application server depending on the workload.

### C. Database administration or migrations

One image may contain multiple compatible scripts or subcommands. By changing arguments, an operator can run the server by default or perform a one-off maintenance operation; ensure the operation's credentials and permissions are appropriate.

### D. Kubernetes / OpenShift mapping

At a high level, Kubernetes Pod specs use `containers[].command` to override an image's ENTRYPOINT and `containers[].args` to override its CMD. This helps operators adapt images to workloads without rebuilding them. Exact behavior still depends on the chosen image and process.

### E. AWS ECS

ECS task definitions support startup command/entry point configuration for containers. The same core ideas apply: know which executable is started and which arguments are supplied, rather than assuming an image always runs its default behavior.

## 9. What this lab does not demonstrate

- It does not deploy a production service.
- It does not prove graceful shutdown of a long-running server, because these examples exit quickly.
- It does not confirm anyone ran the exercise solely because commands are documented.
- It does not guarantee a given image contains every Linux utility.
- It does not provide independently verified outcomes until actual evidence is attached.

**Reproducible commands are a strong learning reference; actual retained execution results are a separate evidence category.**

## 10. Quick self-interview

**Q1. What's the difference between ENTRYPOINT and CMD?**  
Exec-form ENTRYPOINT sets the main executable and any fixed arguments. CMD supplies defaults, or defines the whole startup command when ENTRYPOINT is absent.

**Q2. Does CMD execute after ENTRYPOINT?**  
Not as a separate command in the common exec-form pair. Its array items become additional arguments.

**Q3. What happens if I add an argument after the image name?**  
It replaces the image's default CMD arguments while keeping the configured ENTRYPOINT, unless another override is used.

**Q4. Why does this container stop quickly?**  
The `echo` executable (or script) finishes. Process completion is expected, even in detached mode.

**Q5. Why prefer exec form for long-running services?**  
It avoids an implicit shell and generally makes process and signal handling easier to reason about.

**Q6. Is a shell script an invalid ENTRYPOINT?**  
No. It's common, but the script must be executable, available in the image and designed for correct runtime behavior. It should use `exec` to launch a long-running application where appropriate.

**Q7. Does `--entrypoint` change the image permanently?**  
No. It changes startup behavior for that container invocation.

## Revision in 30 seconds

> **ENTRYPOINT** = what starts. **CMD** = default command or default arguments. **Runtime args** = replace CMD defaults. **`--entrypoint`** = replace executable. **Exec form** = usually clearer process/signal semantics. **The container lives as long as its main process does.**

---

**Practical application:** [Lab 09 runbook](README.md) · **Evidence policy:** [Engineering Proof of Work](../../evidence/PROOF-OF-WORK.md) · **All labs:** [Red Hat 1 lab index](../README.md)
