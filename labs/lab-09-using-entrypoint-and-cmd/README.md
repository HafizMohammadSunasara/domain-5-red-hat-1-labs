# Lab 09 — Using ENTRYPOINT and CMD in Containerfiles

**Track:** Domain 5 → Linux and Open Source → Red Hat 1  
**Purpose:** Practical execution guide, quick revision, and reproducibility reference  
**Completion status:** Documentation prepared; practical completion has **not yet been explicitly confirmed**.  
**Evidence:** Source examples and validation commands are included. No original terminal screenshot, build log, or independently verified result is claimed.

> **Start here:** This is the concise practical guide. For detailed reasoning, signal handling, troubleshooting, and real-world use, read **[DEEP-DIVE.md](DEEP-DIVE.md)**.

## What you learn

- Choose a default startup executable with `ENTRYPOINT`.
- Provide default arguments using `CMD`.
- Override `CMD` by supplying arguments after the image name.
- Override `ENTRYPOINT` using `--entrypoint`.
- Compare exec-form and shell-form container startup.

## Requirements

- Linux with Podman installed, internet access to pull UBI 9 Minimal.
- Text editor or a POSIX shell.
- **Note:** `--rm` deletes the stopped test container, not the image.

## Task 1 — Build an image with ENTRYPOINT + CMD

Instructor's setup command:

```bash
mkdir entrypoint-cmd-lab && cd entrypoint-cmd-lab
```

Create a file named **`Containerfile`** using the following *same instruction content* as the lab:

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal
ENTRYPOINT ["echo", "Entrypoint says:"]
CMD ["Default CMD message"]
```

To reuse the separate source file in this repository, you may copy **[Containerfile.basic](Containerfile.basic)** to `Containerfile`:

```bash
cp Containerfile.basic Containerfile
```

This extra `cp` is a convenience step, not an instructor command.

Build as instructed:

```bash
podman build -t entrypoint-demo .
```

**How it works:** The effective startup is `echo "Entrypoint says:" "Default CMD message"` (exec form). Image build does not execute the `CMD`.

## Task 2 — Test CMD defaults and overrides

Default run:

```bash
podman run --rm entrypoint-demo
```

**Expected**, not a retained terminal log:

```text
Entrypoint says: Default CMD message
```

Override the default `CMD` arguments:

```bash
podman run --rm entrypoint-demo "Custom message"
```

**Expected**:

```text
Entrypoint says: Custom message
```

**Revision:** The executable and its fixed `ENTRYPOINT` argument remain unchanged; the supplied runtime argument replaces `CMD`.

## Task 3 — Script-based ENTRYPOINT

Create **`greet.sh`** (source included in this folder):

```sh
#!/bin/sh
echo "Welcome to $1 from $2"
```

Make it executable:

```bash
chmod +x greet.sh
```

Replace `Containerfile` with the instructor's script example:

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal
COPY greet.sh /usr/local/bin/
ENTRYPOINT ["/usr/local/bin/greet.sh"]
CMD ["OpenShift Lab", "Red Hat"]
```

Or, when using this repository's separate samples:

```bash
cp Containerfile.script Containerfile
```

Build the second image:

```bash
podman build -t greet-demo .
```

Run using default arguments:

```bash
podman run --rm greet-demo
```

**Expected:** `Welcome to OpenShift Lab from Red Hat`

Override both default arguments:

```bash
podman run --rm greet-demo "Container Workshop" "Instructor"
```

**Expected:** `Welcome to Container Workshop from Instructor`

**Revision:** In the script, `$1` is the first argument (`OpenShift Lab`) and `$2` the second (`Red Hat`). The script exits after `echo`; so does the container.

## Task 4 — Override ENTRYPOINT itself

Instructor's exact test:

```bash
podman run --rm --entrypoint echo greet-demo "This completely replaces the ENTRYPOINT"
```

**Expected:** `This completely replaces the ENTRYPOINT`

**Revision:** `--entrypoint echo` replaces the image's configured executable; `greet.sh` is not called. Explicit runtime arguments are passed to `echo`.

## Task 5 — Compare shell form and exec form

Replace `Containerfile` with the lab's shell-form example:

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal
ENTRYPOINT echo "Shell form ENTRYPOINT:"
CMD echo "Shell form CMD"
```

The course does not supply a Task 5 build/run command. To test it yourself, use the supplied [Containerfile.shell](Containerfile.shell):

```bash
cp Containerfile.shell Containerfile
podman build -t shell-demo .
podman run --rm shell-demo
```

**Expected:** `Shell form ENTRYPOINT:`  
The shell-form `ENTRYPOINT` does **not** run the shell-form `CMD` as a second command. This experiment makes the difference visible.

## Quick verification / inspection

```bash
podman images
podman image inspect entrypoint-demo --format '{{json .Config.Entrypoint}} {{json .Config.Cmd}}'
podman image inspect greet-demo --format '{{json .Config.Entrypoint}} {{json .Config.Cmd}}'
```

The output should reflect the image configurations; verify against your actual environment. Image names and available utilities may vary with Podman versions.

## Troubleshooting

| Symptom | Cause to check | Next action |
| --- | --- | --- |
| Script permission denied | `greet.sh` not executable at build time | `chmod +x greet.sh` and rebuild |
| Script not found | Wrong `COPY` path, build context, or CRLF shebang | Check `greet.sh` and LF line endings |
| Image build fails | Network or base-image registry access | Check registry connectivity and exact error |
| Container exits immediately | The `echo` program/script finishes | Expected for this lab; use `podman ps -a` if needed |
| Output differs | CMD override or wrong Containerfile version | Check `podman image inspect` and tag |

## Cleanup (only these lab image tags)

```bash
podman rmi entrypoint-demo greet-demo
```

If you also ran the optional experiment:

```bash
podman rmi shell-demo
```

If any image is still referenced by a container, identify that container before removing it. Avoid global `podman rm -f $(podman ps -aq)`.

## Evidence and limitations

- **Provided:** Reproducible Containerfile variants, a shell script, commands, reasoning, and expected-result criteria.
- **Not provided:** Original execution logs, screenshots, an independently verified test run, or a claimed passing output from this learner's machine.
- **Status:** Update to *Completed — self-reported* only after confirming the practical tasks were performed.
- See the repository-wide [Engineering Proof of Work](../../evidence/PROOF-OF-WORK.md) policy.

**Continue learning:** [Deep Technical Explanation](DEEP-DIVE.md) · [All Red Hat 1 Labs](../README.md)
