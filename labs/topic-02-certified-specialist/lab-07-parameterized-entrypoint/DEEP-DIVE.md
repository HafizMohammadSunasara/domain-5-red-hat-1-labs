# DEEP DIVE — Parameterized `ENTRYPOINT` Scripts

**Container startup internals · Practical reproducibility · Secure scripting · Production engineering mindset**  
Companion: **[Lab 07 README](README.md)**  
Track: Domain 5 → Linux & Open Source → Red Hat 1 → Topic 2  
Maintainer: Hafiz Mohammad Sunasara

> **The question that matters:** *What exact executable starts inside this container, with which arguments, under which user, with which environment—and what evidence proves it?*

This handbook is written for someone who has never worked with container process configuration and wants to become capable of explaining and debugging it, not just copying a successful build command.

## Reading map

1. Start with the process model
2. How a container image records its startup configuration
3. How exec-form `ENTRYPOINT` and `CMD` compose
4. Why a startup shell script is useful
5. Script shebang, executable bits and Alpine shell differences
6. Positional arguments and safe quoting
7. Why `exec "$@"` matters for process lifecycle
8. Runtime arguments, shell-form differences, and override rules
9. Environment variables as configuration
10. Designing trustworthy development/production modes
11. `case` statement dispatch and why `stop` is not a container stop
12. The build-time vs runtime boundary
13. Diagnosing stale-image behavior in the submitted screenshots
14. Exit codes and failure handling
15. PID 1, signals and graceful shutdown
16. Image security and least privilege
17. Secrets, logging and avoiding unsafe shell evaluation
18. Testing matrix and evidence quality
19. Applying concepts to Compose, Kubernetes and OpenShift
20. Design tradeoffs, exercises and interview preparation

---

## 1. Begin with the simplest possible process model

A Linux program runs as a process. It receives (a) an executable, (b) a list of arguments, (c) environment variables, (d) a working directory, (e) file descriptors and (f) a process identity. A container does not magically remove those Linux fundamentals; it packages and constrains the conditions in which the process runs.

Imagine a command on the host:

```bash
/bin/echo "hello" "world"
```

The operating system does not receive an English sentence. The executable path is `/bin/echo`, and the argument list is `hello`, `world`. Those exact argument boundaries matter. `"hello world"` is one argument, whereas `hello world` without quotes is two. In most shells, `$@`, `$*`, and unquoted variable expansion affect how arguments are passed.

For a container, an equivalent image can define what executable should run, and `podman run` can supply additional parameters. Learning this translation is the foundation of every task in the lab.

**Engineer’s question:** If a container exits unexpectedly, is the image broken, the executable missing, the arguments wrong, the permissions insufficient, or the application choosing to exit? Each answer leads to a different debugging technique.

## 2. Images include metadata, not only files

An image combines layered filesystem content with configuration metadata. Metadata can include its default **Entrypoint**, **Cmd**, **WorkingDir**, **User**, **Env**, and exposed ports. Changing a Dockerfile and building a new image changes both filesystem contents and possibly the metadata of the resulting image.

The default process can be examined without guessing:

```bash
podman image inspect lab07-parameters \
  --format '{{json .Config.Entrypoint}}'
podman image inspect lab07-parameters \
  --format '{{json .Config.Cmd}}'
```

The output describes the selected image. These commands do **not** execute the entrypoint. They also do not tell you whether a copied script has the desired logic; for that, run the image or inspect its file content separately.

A running container does not watch your local `entrypoint.sh` for edits. Unless you mount a file at runtime, source files that were `COPY`-ed become part of the image at **build time**.

## 3. Exec-form ENTRYPOINT and CMD: the mental formula

For the exec-form used in this lab, a useful approximation is:

```text
ENTRYPOINT [program, fixed_arg_1, ...] + CMD [default_arg_1, ...]
       → program fixed_arg_1 default_arg_1 ...
```

Consider:

```dockerfile
ENTRYPOINT ["echo"]
CMD ["Default command executed"]
```

Running without extra parameters invokes `echo` with the default text. Running with a replacement value:

```bash
podman run image "Override text"
```

replaces CMD's default arguments with `"Override text"`, while `echo` stays the executable. By contrast, if an image only has `CMD ["echo", "hello"]`, then an appended command after the image name becomes a new command that replaces the whole default.

The CLI has a separate `--entrypoint` option to replace an image's startup executable. Understand both levels: arguments-after-image generally replace CMD, whereas `--entrypoint` replaces ENTRYPOINT.

**Caution:** Shell-form instructions (`ENTRYPOINT echo hello`) introduce a shell that can alter argument and signal behavior. Don't assume the same forwarding guarantees. Prefer JSON-array exec form for a startup program unless there is a deliberate reason to use shell form.

## 4. What is an entrypoint script?

An entrypoint script is an ordinary executable file that you select as the container's startup process. It's often useful for:

- Inspecting configuration and refusing to start when required values are missing.
- Preparing writable runtime directories with safe permissions.
- Selecting an application mode or subcommand.
- Performing a safe one-time initialization when necessary.
- Finally handing control to the actual long-running executable.

It should not be a hidden, unbounded installation program that alters the application unpredictably on every startup. Keep it short, observable, deterministic, and easy to test. A reliable entrypoint should not print credentials or ignore failures.

In Task 1, the basic script only prints `Container starting`, `whoami`, and `pwd`. These are excellent teaching probes because they show the initialization happened and which context the process received. They do **not** mean an application server is running.

## 5. Shebangs, shell compatibility and executable permissions

The first line is interpreted as the script interpreter declaration:

```sh
#!/bin/sh
```

This means the kernel should start `/bin/sh` to interpret the following text. In an Alpine image, BusyBox provides `/bin/sh` by default; `/bin/bash` is generally not present unless explicitly installed. The instructor's `#!/bin/bash` paired with a plain Alpine base can therefore fail with a misleading “no such file or directory.” Using `/bin/sh` and POSIX shell syntax is a portable solution.

You must also make the file executable in the image:

```dockerfile
COPY entrypoint.basic.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
```

Host executable permissions may be copied by the builder, but setting permissions explicitly in the image is clear and reproducible. Mode `755` gives owner write permission and read/execute to others. For production, choose the least permissive ownership/mode compatible with how the file is used.

A Windows-edited file may use CRLF (`\r\n`) rather than LF (`\n`). The shebang can then unintentionally look like `/bin/sh\r`. Normalize script line endings before building if you get a puzzling interpreter error. Also avoid scripts that depend on `bash` constructs (`[[ ... ]]`, arrays, `source`) when declaring `/bin/sh`.

## 6. Positional parameters: `$1`, `$2`, `$#`, `$@`, `$*`

Shell scripts can receive arguments. Suppose:

```bash
/entrypoint.sh echo "Default command executed"
```

The script sees `$1` as `echo` and `$2` as the entire `Default command executed` text. `$#` reports the number of positional parameters. `${1:-none}` returns a fallback when a first argument is unset or empty. `$0` is the invocation name of the script, not the first external argument.

**Important distinction:** `"$*"` turns all positional arguments into one displayable string; it is suitable for friendly logging but loses the original argument boundaries. `"$@"` preserves the original list, one argument per item. That is why the forwarding step uses:

```sh
exec "$@"
```

Do **not** use unquoted `$@` or `eval "$*"` as a shortcut. Unquoted expansion can split arguments and expand filename globs; `eval` can execute shell syntax embedded in input. With user-controlled arguments, that becomes an avoidable injection risk.

To test argument boundaries, compare:

```bash
podman run --rm lab07-parameters echo hello world
podman run --rm lab07-parameters echo "hello world"
```

In the first, after `echo`, there are two additional arguments. In the second, the phrase is one argument. The displayed echo output may look similar, but the parameter count and boundary are different.

## 7. Why `exec "$@"` is better than `"$@"` alone

When a shell script launches a child process normally, the shell stays alive as a parent waiting for that process. If it uses `exec`, the shell process is *replaced* by the target executable in the same process identity (PID), rather than creating a new child and remaining as a wrapper.

For instance:

```sh
printf '%s\n' 'Starting service...'
exec nginx -g 'daemon off;'
```

In a long-running workload, this makes it easier for the real application to receive lifecycle signals sent to the container's main process. It also lets the application's exit code become the container's exit code. Some applications still need a small init process to reap child processes; `exec` is necessary for clean forwarding in many setups, but not the entire lifecycle story.

For short-running commands such as `echo`, the benefit is less visible because the program exits immediately. It's still a useful pattern to learn for real services.

**Common problem:** The script logs arguments successfully, but the command never runs. Possible causes are a missing `exec`, an earlier `exit`, wrong build tag, or an executable name that does not exist. Observing the printed arguments **does not prove execution**. In the supplied Task 2 screenshot, the script logged `hello world` with no evidence of successful downstream command execution.

## 8. Runtime override behavior, precisely

There are three different changes a user can make:

| Choice | Example | Effect |
|---|---|---|
| Accept image defaults | `podman run lab07-parameters` | Runs CMD argument array via ENTRYPOINT |
| Replace CMD args | `podman run lab07-parameters ls -l /` | ENTRYPOINT remains; script receives `ls -l /` |
| Override ENTRYPOINT executable | `podman run --entrypoint /bin/sh lab07-parameters -c 'id'` | Startup script is bypassed; `/bin/sh` becomes executable |

A fourth change is rebuilding the image after editing its Dockerfile or copied script. This is **not** a runtime override; it produces a new image state. If you forget the rebuild, Podman will run the old content regardless of host edits.

Tip: use distinct tags for distinct task states (`lab07-basic`, `lab07-parameters`, `lab07-modes`, `lab07-commands`). This design removes much of the ambiguity in the lesson's repeated use of `entrypoint-demo:latest`.

## 9. Environment variables are inputs, not automatically security controls

An environment variable is a named value visible in the process environment. With Podman:

```bash
podman run --rm -e ENV_MODE=development lab07-modes
```

The process receives `ENV_MODE=development` and the script can inspect it with `${ENV_MODE:-}`. If the variable is missing, the script can choose a predictable default. A stricter script can reject unsupported values rather than silently continuing with risky assumptions.

A script must actually *read* the variable for it to have an effect. Passing `-e ENV_MODE=production` to Podman doesn't magically enable secure file permissions, disable debug endpoints, install TLS, or harden the container. Those properties require real configuration and validation.

Avoid encoding passwords or tokens directly as terminal arguments: they may be visible in shell history and command-line listings. Environment variables also can leak through inspection or logs; use an appropriate secrets mechanism when production credentials are involved.

## 10. Design a mode selector with explicit expectations

A robust mode selector can use `case`:

```sh
case "${ENV_MODE:-}" in
  development)
    printf '%s\n' 'DEVELOPMENT MODE: Debug features enabled (demo message only)' ;;
  production)
    printf '%s\n' 'PRODUCTION MODE: Strict settings applied (demo message only)' ;;
  '')
    printf '%s\n' 'No ENV_MODE specified, running in default mode' ;;
  *)
    printf 'Unsupported ENV_MODE: %s\n' "$ENV_MODE" >&2
    exit 64 ;;
esac
```

This validates accepted values and makes behavior explicit. The message itself is only a demonstration—there must be accompanying application configuration for the label to mean anything operationally. A real production mode might disable a debug server, set structured logging, require TLS to a dependent service, and turn on stricter app input validation. Those changes must be implemented and tested separately.

The expected training result is three clearly different modes. Your supplied Task 3 screenshot shows that all three `podman run` invocations produced the **same argument logging** instead. A highly plausible explanation is that the modified script was not copied into a newly rebuilt image. We can say this possibility is consistent with the screenshot; we cannot prove the exact root cause without the missing script/build state.

## 11. Subcommand dispatch: what `start` and `stop` actually mean

Scripts frequently parse a first argument as a subcommand:

```sh
case "${1:-}" in
  start)
    printf 'Starting application with config: %s\n' "${2:-default}" ;;
  stop)
    printf '%s\n' 'Stopping application gracefully (simulation only)' ;;
  *)
    printf 'Usage: %s {start|stop} [config]\n' "$0" >&2
    exit 64 ;;
esac
```

Here, `$1` chooses the branch and `$2` optionally selects a config label. Unknown input exits nonzero. A consistent usage message and status code are important for automation: a CI job should notice invalid invocations instead of treating them as success.

**Major operational caution:** `podman run IMAGE start ...` and `podman run IMAGE stop` create **different containers**. If the first script just prints a line and exits, there is no service left running to stop. A real containerized service is stopped with `podman stop <container>` (or orchestration controls), which sends termination signals to a running process. Don't describe Task 4's printed “Stopping...” line as proof of graceful shutdown.

A production-grade dispatcher for a long-lived application would typically use `start)` to `exec` the application server; the `stop)` path, if even needed, would contact an existing service through an authenticated channel. That is outside this lab's scope.

## 12. Build-time vs runtime: the source of many silent mistakes

Picture two distinct stages:

```text
HOST SOURCE → podman build → IMAGE LAYERS AND IMAGE CONFIG
                                 |
                                 v
                         podman run → CONTAINER PROCESS
```

`COPY entrypoint.sh /entrypoint.sh` happens during build. `RUN chmod ...` happens during build. The `ENTRYPOINT` instruction stores startup metadata that is interpreted when the container is created. `podman run` uses whichever image version its tag resolves to at that moment.

If you edit the host file but do **not** build again, you haven't changed the image. This is why the sequence matters:

```bash
# After changing the script, always rebuild the intended stage.
podman build --no-cache -f Containerfile.modes -t lab07-modes .
podman run --rm -e ENV_MODE=production lab07-modes
```

Cache can also obscure what you think was rebuilt. `--no-cache` is useful for diagnosing, though it should not be necessary for every normal build. For clarity in teaching, this repository uses four independently named files rather than rewriting a single filename four times.

## 13. Forensic reading of the supplied screenshots

An experienced engineer avoids “it looks fine” and records the exact evidence:

### Screenshot 01 — Basic startup

- The Podman build shows steps involving `FROM alpine:latest`, `COPY entrypoint.sh`, and exec-form `ENTRYPOINT`.
- Running the tagged image prints `Container starting...`, `Executing as user: root`, and `Current directory: /`.
- This supports the claim that the basic entrypoint executed in the training environment.

### Screenshot 02 — Arguments are visible

- The displayed build adds `CMD ["echo", "Default command executed"]`.
- Running with `hello world` shows those values as first/second arguments.
- No `Hello` executable runs; script logging alone does not prove `exec "$@"`.

### Screenshot 03 — Mode branch absent

- The terminal shows Podman runs with `ENV_MODE=development`, `ENV_MODE=production`, and no `ENV_MODE`.
- Output remains `Container starting with arguments...`, `First argument...`, `Second argument...`.
- The expected `DEVELOPMENT MODE`, `PRODUCTION MODE`, and fallback banners are not present.
- The screenshot also shows an `awk` warning during a sed editing attempt; this is a troubleshooting clue, not decisive root-cause proof.

### Screenshot 04 — Dispatch branch absent

- The CLI contains invocations with `start production`, `stop`, and `invalid`.
- Output remains simple argument logging, with no “Starting application with config”, “Stopping application gracefully”, or usage/exit display.
- We cannot claim the `case` script was executed. Rebuilding the task-specific image and rerunning it is the best next validation.

When publishing, keep this distinction visible. Your genuine screenshot is more valuable if the README explains its **actual meaning and limits**.

## 14. Exit statuses turn a script into an automation building block

Unix programs return an exit status. Zero usually means success; nonzero indicates error or special handling. A wrapper should propagate the real application status. Using `exec "$@"` helps because there is no remaining wrapper to accidentally mask the child process's status.

With `set -e`, a script can stop on many command failures, but the rules have exceptions within tests, loops, pipelines and compound conditionals. It is not a substitute for structured error handling. `set -u` treats unset variables as errors; avoid directly reading an unset `ENV_MODE` under `set -u` and use `${ENV_MODE:-}`.

For the Task 4 invalid argument, this repository deliberately exits `64` (command usage error convention). Check it by running:

```bash
podman run --rm lab07-commands invalid
printf 'exit status = %s\n' "$?"
```

Do the print immediately afterward. Any intervening successful command overwrites `$?`.

## 15. PID 1 and graceful termination

Inside a normal container, the initial process is PID 1 in its PID namespace. It has a special lifecycle role: runtimes typically send a termination signal to that process when asked to stop. When a shell entrypoint forks a server without `exec`, the shell is still the main process. Without explicit forwarding, the real server may not receive the signal as intended.

Use `exec` when no more wrapper work remains:

```sh
#!/bin/sh
set -eu
# validate config, create runtime dirs if needed
exec "$@"
```

For applications that spawn many child processes, consider runtime init mechanisms and whether the application reaps children correctly. You should also test shutdown behavior: run a long-lived process, send SIGTERM, observe whether it exits cleanly within the configured grace period and whether data is flushed. This lab's short-lived `echo` scripts do not demonstrate graceful service shutdown.

## 16. Security design: script permissions and least privilege

Your Task 1 prints `root`. That describes the container process identity for a default Alpine image—not necessarily a host-root identity. For real applications, aim for non-root runtime users and limited Linux capabilities. This follows the principles from Topic 2 Lab 04 and Lab 05.

An entrypoint running as container root can change filesystem permissions or install packages, but this may become a security risk. Prefer performing installations during the build stage, not every startup. Ensure the executable script is immutable to the app user where practical, and minimize writable paths. A read-only root filesystem can provide additional protection if your app's temporary directories are configured separately.

Avoid privileged mode simply to make a startup script work. Debug the exact required permission. `--privileged` is a drastic change and not an appropriate routine workaround.

## 17. Logs, secrets and input validation

Logging command-line arguments (`$*`) is convenient for learning but may expose credentials if developers pass secrets as arguments. Never log passwords, access keys, or tokens. Use environment variables only with caution and avoid printing their values. In orchestrated environments, use secret injection with controlled file permissions and access policies.

Treat configuration strings as data. Quote expansions in test and output statements. The Task 4 `case` pattern is safer than constructing shell commands from arbitrary user values. Avoid `eval`. Make supported options explicit and reject unsupported values with a clear error message.

When moving from demonstration to production, consider container logs, startup timeout, readiness checks and a documented environment-variable contract.

## 18. A small engineering test matrix

A good test doesn't just ask “Did it return 0?” It predicts expected output and explains failure cases.

| Scenario | Run | Expected signal of correctness |
|---|---|---|
| Task 1 startup | `podman run --rm lab07-basic` | root and `/` printed as configured |
| Default CMD | `podman run --rm lab07-parameters` | Logger plus `Default command executed` |
| Override default | `podman run --rm lab07-parameters ls -l /` | Root directory listing from real `ls` |
| Development mode | `-e ENV_MODE=development lab07-modes` | Development banner |
| Production mode | `-e ENV_MODE=production lab07-modes` | Production banner |
| Unset mode | `lab07-modes` | Explicit fallback banner |
| Invalid mode | `-e ENV_MODE=qa lab07-modes` | Nonzero exit, clear error |
| Start with config | `lab07-commands start production` | “Starting ... production” message |
| Stop (demo) | `lab07-commands stop` | Simulation message, not an actual service stop |
| Invalid subcommand | `lab07-commands invalid` | Usage and exit status 64 |

Record the command and its actual output together in your evidence screenshots. A screenshot of a course page is instructional context only. If a test did not produce the expected output, record **observed vs expected**, possible causes, and how to retest.

This is the evidence standard that makes a public engineering journal credible.

## 19. Compose, Kubernetes and OpenShift integration

At higher abstraction levels, the same Linux process principles remain. A Compose service can override an image's `entrypoint` or `command`, supply environment variables, or mount configuration. Kubernetes pod `containers[].command` corresponds conceptually to an image's entrypoint; `containers[].args` corresponds to default arguments. Exact behavior depends on the runtime specification and the workload manifest.

Example conceptual Kubernetes configuration:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: entrypoint-demo
spec:
  containers:
    - name: sample
      image: example-registry.invalid/team/app@sha256:REPLACE_WITH_REAL_DIGEST
      command: ["/entrypoint.sh"]
      args: ["echo", "hello from pod"]
      env:
        - name: ENV_MODE
          value: "development"
```

**This manifest is illustrative and not deployable as-is**: the image/digest placeholder intentionally is not real. The example demonstrates the mapping of a runtime command, arguments and environment. OpenShift may enforce security contexts such as arbitrary UIDs or restricted writable filesystem paths, so test scripts without assuming root.

For reliable production workloads, add readiness/liveness/startup probes, resource limits, graceful termination, permissions for arbitrary UID execution, and secret handling. Parameterized entrypoints are one small part of container reliability.

## 20. Design patterns: make startup predictable

### Pattern A — Minimal wrapper

Use a short script to validate required configuration and then `exec` the application. Suitable for many web servers and workers. Keep installation out of startup.

### Pattern B — One-shot job container

Set a default command for a migration or batch task. Arguments can choose input data, but validation and exit status must be strict. Jobs should be safe to retry or document whether they are idempotent.

### Pattern C — Dispatcher

Accept a short allowlist of subcommands (`serve`, `migrate`, `healthcheck`) and map each to explicit executables. Avoid shell-based dynamic evaluation. The Task 4 `start`/`stop` exercise is a beginner illustration, not a real service manager.

### Pattern D — Configured startup

Use a validated environment selector for application settings while keeping secrets separate. Prefer immutable images and configuration at deployment time over per-environment image forks when it suits the app.

### Mistakes to avoid

- Using `#!/bin/bash` on bare Alpine without installing Bash.
- Forgetting the image rebuild after modifying copied sources.
- Reusing a single mutable `latest` tag for several unrelated tests without checking which version is running.
- Treating printed arguments as proof that `exec` ran an application.
- Using `eval` on untrusted arguments or printing secrets.
- Claiming `start`/`stop` dispatch proved service lifecycle behavior.
- Assuming a production-labeled message enabled actual security hardening.

---

## Interview practice — 20 questions and answers

**1. What is ENTRYPOINT?**  
It defines the executable the container normally starts. Exec form stores a program plus fixed arguments without wrapping it in a shell.

**2. What is CMD?**  
It provides a default command when no entrypoint is set, or default arguments when an entrypoint is defined, depending on how the image is configured.

**3. What happens to CMD when runtime arguments are supplied?**  
In exec-form `ENTRYPOINT` examples, the arguments after the image replace the CMD defaults.

**4. How can the user override ENTRYPOINT?**  
With a runtime flag such as Podman's `--entrypoint`, or a higher-level workload's command override.

**5. Why use a shell script as ENTRYPOINT?**  
To validate configuration, prepare runtime prerequisites, dispatch a known command, and finally start the application.

**6. Why choose `/bin/sh` for Alpine?**  
Because it exists in the base image; Bash often does not.

**7. What does `chmod +x` solve?**  
It grants execute permission to the script file. It does not fix an invalid shebang or Windows CRLF line endings.

**8. What is `$1`?**  
The first argument passed to the script; `$0` is the script's invocation name.

**9. What is the difference between `"$*"` and `"$@"`?**  
`"$*"` produces a combined string; `"$@"` preserves individual arguments for safe forwarding.

**10. Why use `exec "$@"`?**  
It replaces the shell with the requested program, improving signal delivery and exit-status semantics for the primary process.

**11. Can you use `hello world` as a forwarded command?**  
Only if an executable named `hello` actually exists. For a demonstration, `echo hello world` is valid.

**12. Does changing an entrypoint file on the host update the image?**  
No. `COPY` happens at build time. Rebuild (or deliberately bind-mount) to incorporate changes.

**13. Why did the training screenshot show no development/production banner?**  
It used `ENV_MODE` CLI flags, but output stayed at the older logger; the exact cause isn't proven. A missing image rebuild or wrong script is a plausible explanation.

**14. Why validate `ENV_MODE` rather than assuming anything?**  
To avoid silent misconfiguration and to make unsupported values fail clearly.

**15. Is an ENV_MODE=production label proof of secure production configuration?**  
No. Security properties require actual settings and tests.

**16. Does `podman run image stop` stop another container?**  
No. It creates another container and runs that image with `stop` as an argument. A running container is stopped with `podman stop` or an orchestrator.

**17. What is PID 1?**  
The initial process in the container's process namespace, which receives lifecycle signals from the runtime.

**18. How do you inspect startup metadata?**  
Use `podman image inspect` to view the image's configured Entrypoint, Cmd, User, Env and WorkingDir.

**19. How should invalid subcommands behave?**  
Print a useful error or usage message and exit with a nonzero status so automation can detect the failure.

**20. What is your main engineering takeaway from this lab?**  
Understand the build/runtime boundary and verify the specific behavior. A successful build and an argument log are weaker evidence than a test that proves the intended application or mode actually executed.

---

## Extension exercises for deeper mastery

**Exercise A:** Add a non-root runtime user and see which directories your startup process can write to. Use lessons from Lab 04, then document `id` and file permissions.

**Exercise B:** Replace the demonstration `echo` with a long-lived service and test `podman stop` behavior. Measure whether SIGTERM reaches the application and whether it exits inside the grace period.

**Exercise C:** Build the same configuration twice using a pinned digest, then compare relevant runtime metadata and output. Explain why mutable tags are less reproducible.

**Exercise D:** Add an environment validation rule rejecting arbitrary values. Show a nonzero exit status and a useful error log for `ENV_MODE=unknown`.

**Exercise E:** Implement small shell-only tests that capture expected stdout, stderr and exit status, then run them in CI. Avoid privileged runners or real secrets.

**Exercise F:** Contrast image default CMD with a Compose `command:` override and Kubernetes `args:` override. Write down the exact process/arguments visible inside the container.

## Cheat sheet

```text
Build:
  podman build -f Containerfile.parameters -t lab07-parameters .

Run default CMD through entrypoint:
  podman run --rm lab07-parameters

Replace CMD arguments:
  podman run --rm lab07-parameters ls -l /

Pass environment configuration:
  podman run --rm -e ENV_MODE=production lab07-modes

Replace ENTRYPOINT entirely:
  podman run --rm --entrypoint /bin/sh lab07-parameters -c 'id'

Inspect image configuration:
  podman image inspect lab07-parameters --format '{{json .Config.Entrypoint}}'

Remember:
  Source edit ≠ image update. Rebuild and rerun to prove behavior.
```

**[Back to the lab README](README.md)** · [View real evidence](README.md#evidence-and-limitations)
