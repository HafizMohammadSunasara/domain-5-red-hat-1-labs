# Deep Dive — Mastering Container Startup: `CMD`, `ENTRYPOINT`, Process 1, and Runtime Overrides

**Companion exercise:** [Lab 06 README](README.md)  
**Track:** Domain 5 → Red Hat 1 → Topic 2 · **Date:** 24 October 2026  
**Level:** First container → confidently diagnosing and designing process startup  
**Format:** Concepts · practical commands · mistakes · applied scenarios · interview questions

> **Central question:** When you run a container image, *which program starts, which arguments does it receive, and which part can the operator change without rebuilding?*

**Evidence:** Actual learner screenshots are located in [`evidence/`](evidence/). Technical explanations below extend beyond the original training exercise. Examples in this guide are **reproducible demonstrations**, not claims that each extension was executed in the recorded lab session.

## Reading path

| Level | Sections | Outcome |
|---|---|---|
| Fundamentals | 1–5 | Explain image commands and read Containerfiles correctly |
| Hands-on | 6–10 | Predict outputs, change defaults, write reliable wrappers |
| Engineering | 11–16 | Understand PID 1, Kubernetes, security, testing and debugging |
| Confidence | 17–20 | Diagnose failure scenarios and answer practical interview questions |

---

## 1. Start with the right mental model

A container is **not a tiny virtual machine** that needs its own complete operating-system boot sequence. It is one or more processes using an isolated view of system resources. An OCI image describes layers of filesystem content plus a set of default runtime configuration values.

When Podman launches a container, it creates the required environment and starts the image's configured process (unless the operator replaces it). If that main process exits, the container normally stops.

For this lab, Alpine supplies a minimal environment and the `echo` program. The *Dockerfile/Containerfile* supplies startup defaults. `podman run` can supply different runtime commands or arguments.

Think in terms of three stages:

```text
AUTHOR / BUILD                        OPERATOR / RUN              PROCESS
-------------------------------       -----------------------     ----------------------
Containerfile                         podman run IMAGE ...        What actually executes?
  FROM alpine                         add/override args          exit code? stdout?
  ENTRYPOINT ["program"]      --->   --entrypoint override --->  receives signals?
  CMD ["default-argument"]
```

The image is a **recipe for starting a process**. The container is the **running instance**. You can run the same image many times with different arguments without rebuilding it.

### Why this matters to a DevOps engineer

A perfectly built image might still fail because:

- the wrong executable is selected;
- a user-supplied argument replaced a command rather than being appended;
- the program expects a working directory that is missing;
- a shell script lacks executable permission;
- the wrapper shell swallows termination signals;
- a Kubernetes `command` field overrides a carefully designed image entrypoint.

If you understand the startup configuration, debugging these issues becomes much faster.

---

## 2. `CMD`: a default that the operator can replace

### Minimal example

```dockerfile
FROM docker.io/library/alpine:latest
CMD ["echo", "hello from cmd"]
```

This tells the runtime: **if the user does not supply another command, run `echo` with argument `hello from cmd`.**

Build once:

```bash
podman build -t cmd-demo -f Containerfile.cmd .
```

Run normally:

```bash
podman run --rm cmd-demo
# hello from cmd
```

Run with another complete command:

```bash
podman run --rm cmd-demo echo "Overridden command"
# Overridden command
```

**Why the result changed:** In this image there is no ENTRYPOINT. Arguments supplied after the image name are interpreted as a replacement for the default CMD (including the executable).

### Common misunderstanding

`CMD` does **not** mean “this line is executed during `podman build`.” It is stored as image runtime metadata. `RUN`, by contrast, performs an action during the build and produces the resulting filesystem changes.

```dockerfile
RUN echo "built now" > /tmp/build.txt
CMD ["cat", "/tmp/build.txt"]
```

The `RUN` creates the file when building the image. `CMD` reads it when running a container from that image.

### Multiple CMD instructions

In a single build stage, only the **last effective `CMD`** supplies the resulting CMD configuration:

```dockerfile
CMD ["echo", "one"]
CMD ["echo", "two"]
```

Default runtime output is `two`. Use a single well-defined default instead of relying on overwritten configuration.

---

## 3. `ENTRYPOINT`: a selected executable

### Minimal example

```dockerfile
FROM docker.io/library/alpine:latest
ENTRYPOINT ["echo", "hello from ENTRYPOINT"]
```

```bash
podman build -t entrypoint-demo -f Containerfile.entrypoint .
podman run --rm entrypoint-demo
# hello from ENTRYPOINT

podman run --rm entrypoint-demo "with appended text"
# hello from ENTRYPOINT with appended text
```

Here the image is designed to behave almost like an executable on your host: you choose **arguments**, not normally the program itself.

Conceptually:

```text
Image ENTRYPOINT = ["echo", "hello from ENTRYPOINT"]
User supplied args = ["with appended text"]
Final argv        = ["echo", "hello from ENTRYPOINT", "with appended text"]
```

An ENTRYPOINT is **not immutable or a security boundary**. Podman/Docker can accept a runtime `--entrypoint` override. Never use ENTRYPOINT as your only defense against someone running other commands.

### When to choose ENTRYPOINT

A command-line utility image is a good example:

```dockerfile
ENTRYPOINT ["python", "/app/tool.py"]
```

Then an operator could run `podman run mytool --help` or `podman run mytool --input records.csv`, as long as the program implements those flags. Those arguments would be passed to the same executable.

---

## 4. Exec form versus shell form

This is the source of many confusing runtime bugs. Both `CMD` and `ENTRYPOINT` have forms that **look similar but work differently**.

### Exec form — JSON array

```dockerfile
ENTRYPOINT ["echo", "hello"]
CMD ["world"]
```

The runtime executes the named program directly with the array elements as arguments. **There is no automatic shell interpolation** such as `$HOME`, pipes, globs, or `&&` processing.

### Shell form — plain text

```dockerfile
CMD echo "$HOME"
```

The system generally executes this through a shell (e.g., `/bin/sh -c` for Linux), so shell features can be available. But the shell becomes part of the process startup chain and changes signal/argument behavior.

### Why exec form is often preferred

- Arguments are explicit and not accidentally split by a shell.
- The application can become PID 1 directly when no wrapper is used.
- Signal handling is typically easier to reason about.
- Runtime overrides behave predictably in combination with exec-form ENTRYPOINT.

Shell form is still useful when you truly require shell operations. When shell behavior is needed, consider making it explicit:

```dockerfile
CMD ["/bin/sh", "-c", "echo "$HOME""]
```

**Careful:** Quoting in a JSON-array string is easy to get wrong; the above line is **not valid JSON** because the inner quotes are unescaped. A correct option is:

```dockerfile
CMD ["/bin/sh", "-c", "echo \"$HOME\""]
```

or store the logic in a separate script and use exec-form ENTRYPOINT to call that script.

### Quick rule

If the program accepts normal command-line arguments, start with **exec-form ENTRYPOINT** and **exec-form CMD**. Reach for a shell only when shell behavior is part of the requirement.

---

## 5. The combined pattern: executable + default arguments

```dockerfile
FROM docker.io/library/alpine:latest
ENTRYPOINT ["echo"]
CMD ["DEFAULT MESSAGE"]
```

The effective process invocation is the ENTRYPOINT array **followed by** the CMD array.

```bash
podman run --rm combined-demo
# DEFAULT MESSAGE

podman run --rm combined-demo "Custom message"
# Custom message
```

### Predict the output before running

| Image defaults | User supplies | Effective process |
|---|---|---|
| `ENTRYPOINT ["echo"]`, `CMD ["DEFAULT MESSAGE"]` | nothing | `echo 'DEFAULT MESSAGE'` |
| same | `"Custom message"` | `echo 'Custom message'` |
| same | `one two` | `echo one two` |
| same | `echo hello` | `echo echo hello` (because `echo` remains the entrypoint) |

The last example is the classic trap. Users think the extra `echo` becomes a new executable, but **the existing ENTRYPOINT is still running**.

### Why the combination is useful

Suppose a container always launches `/usr/local/bin/backup` but defaults to an incremental backup:

```dockerfile
ENTRYPOINT ["/usr/local/bin/backup"]
CMD ["--mode", "incremental"]
```

An operator can choose a full backup by passing `--mode full`. The intended tool stays constant. In a real backup system, paths, permissions, credentials and monitoring still need to be designed separately.

---

## 6. Build context, `-f`, and why the trailing dot matters

Podman build syntax includes:

```bash
podman build -t NAME -f CONTAINERFILE CONTEXT
```

For this lab, use `.` for the context:

```bash
podman build -t script-demo -f Containerfile.script .
```

The flags mean:

- `-t script-demo`: give the resulting image a local name/tag;
- `-f Containerfile.script`: use this specific file as the build instructions;
- `.`: send the current directory as the build context. This enables `COPY entrypoint.sh /entrypoint.sh`.

If the build fails saying a source file cannot be found, always check `pwd`, `ls -l`, the selected `-f` path and the build context first.

Do not confuse the **current shell directory on the host** with a container image's `WORKDIR` or its runtime working directory. They are distinct concepts.

---

## 7. Read image configuration without running it

Use Podman inspection to understand exactly what was built:

```bash
podman image inspect cmd-demo --format '{{json .Config.Cmd}}'
podman image inspect entrypoint-demo --format '{{json .Config.Entrypoint}}'
podman image inspect combined-demo --format '{{json .Config.Entrypoint}} {{json .Config.Cmd}}'
```

Expected conceptual values for the provided files:

```text
["echo","hello from cmd"]
["echo","hello from ENTRYPOINT"]
["echo"] ["DEFAULT MESSAGE"]
```

A specific Podman version may format these values differently. The **semantics**, rather than spacing or capitalization, are what matter.

Inspection is particularly useful if a container exits immediately or the repository's Containerfile does not match the image that someone actually deployed.

### Also inspect runtime logs and status

```bash
podman ps -a
podman logs CONTAINER_NAME
podman inspect CONTAINER_NAME
```

`ps -a` displays stopped containers too; `logs` displays what the application wrote; `inspect` reveals detailed runtime configuration and exit state. These commands answer different questions.

---

## 8. Why short-lived containers immediately exit

All four examples in this lab use `echo`, `ls`, or a wrapper that invokes `echo`. These commands run, print something, and exit successfully. **The container is supposed to stop**.

A typical error by beginners is: “My container exited, so it failed.” That is incorrect for one-shot jobs. Successful completion can mean exit code `0` and a stopped container.

To inspect the exit code of a one-shot process:

```bash
podman run --rm combined-demo
printf 'Shell exit status: %s\n' "$?"
```

To keep a service running, its main process must normally remain in the foreground. For example, Nginx containers often use `nginx -g 'daemon off;'` so the container lifecycle tracks the server process.

---

## 9. Shell scripts as ENTRYPOINT: what happens line by line

The course's wrapper is:

```sh
#!/bin/sh
echo "Starting container with arguments: $@"
exec "$@"
```

### Line 1: `#!/bin/sh`

The **shebang** tells Linux which interpreter to use. Without a valid interpreter path, launching the script directly can fail with an execution error.

### Line 2: log the incoming arguments

`"$@"` expands to the positional parameters in the shell context. Inside a quoted string used for `echo`, the result is suitable for a simple demonstration, but it is **not a perfect structured argument logger**—arguments containing whitespace are not reliably distinguishable in the printed line.

### Line 3: `exec "$@"`

This is the crucial line. Quoted `"$@"` preserves argument boundaries when passed to `exec`, and `exec` replaces the shell process with the supplied command if successful. That avoids leaving an unnecessary shell as the parent of the real application.

When the CMD is `['echo', 'Default execution']`, the wrapper receives two arguments. It logs them, then effectively performs:

```sh
exec echo "Default execution"
```

The captured evidence shows both the startup line and the resulting output.

### Important edge case

If there are **no arguments**, `exec "$@"` cannot start an application. For a robust production wrapper, validate inputs and provide a clear failure message. The course lab includes a default CMD, so this issue does not arise in the normal path.

---

## 10. How `--entrypoint` changes the whole startup program

This command appears in the course exercise:

```bash
podman run --rm --entrypoint /bin/ls script-demo -l /
```

Here:

- `--entrypoint /bin/ls` tells Podman to start `/bin/ls` instead of `/entrypoint.sh`;
- `script-demo` identifies the image;
- `-l /` becomes arguments for `ls`;
- the default script's logging and `exec` steps are **not run**.

The retained screenshot shows a listing of directories such as `/bin`, `/etc`, `/home`, and `/tmp`, which is consistent with the override.

This is operationally helpful for **debugging images** that fail to start normally. It is not intended as an authorization mechanism: anyone with sufficient rights to run the image may select a different entrypoint.

---

## 11. PID 1, Linux signals, and graceful termination

Each PID namespace presents its own process numbering. The main container process commonly appears as **PID 1 inside the container**. PID 1 has special responsibilities and signal behavior on Linux.

A naive wrapper might start the application without `exec`:

```sh
#!/bin/sh
myserver "$@"
```

Depending on how the shell runs and waits for the child, the shell may remain PID 1 and the application may not receive shutdown signals as expected.

A more predictable wrapper for a single long-running application is:

```sh
#!/bin/sh
# Do small, required initialization here.
exec myserver "$@"
```

Because `exec` replaces the shell, the server becomes the relevant container process and can receive lifecycle signals directly. But this **does not guarantee a graceful shutdown**: the application itself must handle termination signals correctly and release resources within any configured grace period.

### Safe diagnostic idea

For a real service, inspect the process tree, send a normal stop request, and observe logs and exit time. Test under the exact runtime and orchestration system you use. The present `echo` lab does not test long-running graceful shutdown behavior.

---

## 12. How this maps to Kubernetes

Many learners are surprised because Kubernetes uses names that look reversed from everyday language:

| Dockerfile / OCI image | Kubernetes Pod `containers[]` field |
|---|---|
| `ENTRYPOINT` | `command` |
| `CMD` | `args` |

Example image:

```dockerfile
ENTRYPOINT ["echo"]
CMD ["DEFAULT MESSAGE"]
```

A Pod could override the default arguments with:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: echo-example
spec:
  restartPolicy: Never
  containers:
    - name: echo
      image: your-registry/echo-image:tag
      args: ["Kubernetes override"]
```

**Important:** `your-registry/echo-image:tag` is a placeholder and must be replaced by an actual pushed image reference to deploy this Pod.

To override the executable itself, set `command:`. `args:` overrides image CMD. A change to `command`/`args` is runtime Pod configuration, not a Dockerfile rewrite.

### Why application engineers care

A valid image that runs with Podman can fail in a Kubernetes Pod if:

- the chart supplies `command` and unintentionally bypasses its startup wrapper;
- supplied `args` omit a required flag;
- the image's working directory or path assumptions are false;
- the command exits quickly but the Pod's restart policy expects a long-running service.

Knowing the exact mapping saves substantial troubleshooting time.

---

## 13. CMD and ENTRYPOINT do not implement security

`ENTRYPOINT` is about **default behavior**. It is not a sandbox, a privilege boundary or an access-control mechanism.

To secure a container, consider separate controls:

- `USER` to avoid running as root when possible;
- dropping unnecessary Linux capabilities;
- read-only root filesystem where compatible;
- careful filesystem ownership and volume mounts;
- network exposure and secrets handling;
- vulnerability scanning, base-image updates and provenance verification;
- runtime security policies (seccomp, SELinux/AppArmor where available).

The **least-privilege** ideas you learned in Lab 05 apply regardless of CMD/ENTRYPOINT design. A malicious or mistaken runtime operator with powerful host privileges can often override the command. Do not overstate what a wrapper script can protect.

---

## 14. Reproducibility and image provenance

The lab uses `alpine:latest` because the lesson does. That is fine for a simple learning exercise. A mutable tag can point to different content later, so a rebuild on another date may pull a different image.

For repeatable engineering:

1. Choose a supported base release.
2. Pin to an actual registry digest when strict content identity is needed.
3. Preserve the exact Containerfile and startup script in version control.
4. Test startup behavior in CI, including default and override cases.
5. Record runtime/tool versions when investigating discrepancies.

Do **not** invent a digest or a build result. If you want to report an exact image hash, obtain it from a real registry or local Podman inspection at execution time.

---

## 15. Debugging flow for a failed container startup

Follow this sequence instead of randomly editing Dockerfiles:

```text
Container fails / exits unexpectedly
             |
      Check exit code
             |
    podman ps -a; logs
             |
    Inspect actual image:
    Config.Entrypoint + Config.Cmd
             |
     Is the executable present?
       |              |
      No             Yes
       |              |
  fix path/COPY    test argv and permissions
                      |
                 shell script?
                      |
            check shebang + LF + chmod
                      |
              test --entrypoint
                      |
             retry + archive evidence
```

### Diagnostic commands

```bash
podman image inspect script-demo --format '{{json .Config.Entrypoint}} {{json .Config.Cmd}}'
podman run --rm --entrypoint /bin/sh script-demo -c 'ls -l /entrypoint.sh; head -n 1 /entrypoint.sh'
podman run --rm script-demo
```

The shell override is for the disposable Alpine demo. Do not assume every minimal production image includes `/bin/sh`.

---

## 16. Common errors, explained as causes rather than memorized fixes

### `executable file not found`

The runtime tried to launch a program that was not on PATH or did not exist at the requested absolute path. Check `ENTRYPOINT` and CMD array elements, file installation, `PATH`, and your actual image contents.

### `permission denied` on `/entrypoint.sh`

The file exists but may not be executable by the process user. The lab's Containerfile runs `chmod 0755 /entrypoint.sh` during build. Verify permissions after COPY, not only on the host.

### `exec format error`

Potential reasons include wrong CPU architecture, an invalid script interpreter, or missing shebang. On Windows-created scripts, carriage-return line endings (`CRLF`) can make an interpreter path effectively invalid. Save executable shell scripts with LF endings.

### Expected a custom argument, got a new command

You may be running a **CMD-only** image. Runtime values after the image replace CMD. Use the combined pattern if you intend fixed program + replaceable arguments.

### Expected a full override, but the command was appended

You may be running an **ENTRYPOINT** image. Use `--entrypoint` to replace the executable, or intentionally change the image design.

### Container exits with status 0

For `echo` and `ls` this is normal. A stopped container is not automatically a failed container. Judge success by exit code and required output, not by the process remaining alive.

### Script seems to ignore shell syntax

Exec-form arguments do not go through a shell. If you pass `"echo hello && echo world"` to an executable, that is just a string argument unless some program explicitly parses it. Use a shell script when a sequence of operations is genuinely required.

---

## 17. Practical experiments for deeper confidence

These are **optional exercises**; they were not documented as completed in the original five screenshots.

### Experiment A — Replace the combined image's executable

```bash
podman run --rm --entrypoint /bin/ls combined-demo /
```

Question: why doesn't `echo` run? Because `--entrypoint` replaced it.

### Experiment B — Show complete command replacement in CMD-only image

```bash
podman run --rm cmd-demo /bin/uname -s
```

Question: which CMD value survives? None of the prior default command; the supplied program replaces it.

### Experiment C — Inspect a configured CMD

```bash
podman image inspect combined-demo --format '{{json .Config.Cmd}}'
```

Question: does the output show runtime arguments passed in a **previous** container run? No. It shows image defaults. A run override does not mutate the image.

### Experiment D — Explain how Podman output proves learning

Build alone only confirms the image was created. To prove **override behavior**, compare two runs of the **same image** with and without added arguments. That is why separate runtime screenshots are stronger than a screenshot of `podman images` alone.

---

## 18. Three real engineering scenarios

### Scenario A — An application should always start with Python

Use `ENTRYPOINT ["python", "/app/service.py"]` and sensible default CMD arguments. Operators can change flags without swapping out the Python program accidentally. Add validation for config and error exit codes.

### Scenario B — A database image needs initialization

A wrapper might validate environment variables, initialize data when appropriate, then `exec` the database server. The wrapper must avoid leaking passwords in logs and must not reinitialize a persistent volume on every restart. Startup policy and data persistence are **separate** concerns.

### Scenario C — A Kubernetes Pod crash-loops

Start with actual image metadata and the Pod's `command`/`args`, then logs and exit reasons. It may be a command mismatch, missing executable, permissions problem, app crash, or probe failure. A healthy image build is only one input.

---

## 19. Interview questions with meaningful answers

**1. What is CMD?**  
An image's default command, or default arguments when an exec-form ENTRYPOINT is also set. It can be replaced at runtime.

**2. What is ENTRYPOINT?**  
The image's configured main executable (or command, depending on form), which normally receives runtime arguments. It can be explicitly overridden.

**3. Why does `podman run cmd-demo echo new` replace the whole command?**  
The image has CMD only; the user-supplied command replaces it.

**4. Why does `podman run entrypoint-demo extra` append?**  
The exec-form ENTRYPOINT remains the selected executable, so extra becomes an argument.

**5. What is the best pattern for a CLI-tool container?**  
Usually exec-form ENTRYPOINT for the tool and CMD for optional default arguments.

**6. How do you fully replace ENTRYPOINT?**  
Use a supported runtime override such as `podman run --entrypoint /bin/ls IMAGE ...`.

**7. Does ENTRYPOINT prevent unauthorized code execution?**  
No. It controls defaults, not host/container authorization.

**8. What differs between `RUN` and CMD?**  
RUN executes during image build; CMD defines what happens when a container starts.

**9. Can a Containerfile have multiple CMD instructions?**  
Yes syntactically, but only the final effective CMD takes effect in that build stage.

**10. What is exec form?**  
An explicit JSON-array syntax such as `["nginx", "-g", "daemon off;"]`, which does not automatically invoke a shell.

**11. What is shell form?**  
A plain-text command typically evaluated through a shell. Shell parsing and process behavior can differ from exec form.

**12. Why is `exec "$@"` useful?**  
It replaces a wrapper shell with the selected command and preserves individual argument boundaries.

**13. Why is a shebang important?**  
It tells the system which interpreter should run a script launched as an executable.

**14. Why might a Windows-edited script fail in Linux?**  
Incorrect line endings or invalid interpreter specification may make execution fail.

**15. Why does an `echo` container stop?**  
Because the main process completes; a stopped container can be a successful job.

**16. How do you inspect actual defaults?**  
`podman image inspect IMAGE` and fields such as `.Config.Entrypoint` and `.Config.Cmd`.

**17. How are these configured in Kubernetes?**  
Pod `command` maps to ENTRYPOINT, while `args` maps to CMD; runtime overrides are Pod configuration.

**18. Does changing runtime CMD arguments alter the image?**  
No. A single image may be run with different startup arguments; the image remains the same.

**19. What does a successful `podman build` prove?**  
That the image-building steps succeeded in that environment; it does not prove the application starts or stays healthy.

**20. What evidence is convincing for this lab?**  
A successful build, default and overridden runs, wrapper behavior, entrypoint override, and final tagged image inventory, clearly distinguished from expected examples.

---

## 20. Final cheat sheet and study reflection

| Goal | Pattern / command |
|---|---|
| Default replaceable command | `CMD ["echo", "hello"]` |
| Fixed executable | `ENTRYPOINT ["echo"]` |
| Fixed executable + default args | `ENTRYPOINT ["echo"]` and `CMD ["hello"]` |
| Replace CMD only | `podman run IMAGE newcommand ...` |
| Supply args to ENTRYPOINT | `podman run IMAGE arg1 arg2` |
| Replace ENTRYPOINT | `podman run --entrypoint /bin/ls IMAGE /` |
| Preserve correct script argv | `exec "$@"` |
| Inspect image startup metadata | `podman image inspect IMAGE` |
| Clean temporary container after exit | `podman run --rm IMAGE` |
| Build with selected Containerfile | `podman build -f Containerfile.NAME -t image-name .` |

**What the five screenshots actually establish:** A successful CMD demo and override, an ENTRYPOINT demo with appended text, a combined entrypoint/default-argument demo, the wrapper script with a full runtime override, and the existence of four locally built image tags in a Podman session.

**What the screenshots do not establish:** How these specific images behave under Kubernetes, production signal/shutdown guarantees, security hardening, CI/CD deployment, or performance results. Those are *next-step learning opportunities*, not achieved outcomes.

### Three questions to ask yourself after any container build

1. What executable will be PID 1 when this container runs, and why?
2. Which inputs can the operator override, and what happens if they do?
3. What runtime test—not just build output—would prove the application behaves as intended?

If you can answer all three, you are no longer memorizing CMD and ENTRYPOINT. You are reasoning about process execution like an infrastructure engineer.

---

**Back to [Lab 06 README](README.md)** · **Open [Evidence 01](evidence/01-cmd-default-and-override.png)** · **Open [Evidence 05](evidence/05-final-images-verification.png)**

*Learning record — not a claim of production deployment, certification or full-system validation.*
