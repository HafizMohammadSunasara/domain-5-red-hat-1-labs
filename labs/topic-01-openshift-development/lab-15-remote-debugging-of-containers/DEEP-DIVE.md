# Lab 15 — Engineering Deep Dive: Remote Debugging of Containers

**Domain 5 → Linux and Open Source → Red Hat 1**  
**Related lab:** [Practical runbook](README.md)  
**Learning status:** Completed — self-reported; sample code and expected behavior below are educational references, not archived execution logs.

## 1. What problem does this lab solve?

A live application may return an unexpected value while logs show no clear exception. For example, a checkout handler returns an incorrect total. Adding many `console.log()` statements could help, but an interactive debugger gives a more direct view of the exact execution state: function parameters, intermediate values, call stack and branches.

**Remote debugging** means the debugger UI (e.g. VS Code) connects to a process that is already running somewhere else—in this lab, inside a Podman container. “Remote” means **separate execution context**, not necessarily a distant cloud machine; IDE and container can share one host.

This is primarily a **development/staging technique**. Production debugging usually starts with logs, metrics, traces and safe diagnostics. Pausing a production process may interrupt user requests, and an exposed debugger endpoint can allow arbitrary code execution.

## 2. Architecture: the two network ports

```text
VS Code source workspace
  /home/user/.../app.js (or corresponding Windows source)
       │ source-path mapping
       ▼
VS Code Node debugger  ───── local TCP 9229 / WebSocket ────┐
                                                           │
Host networking                -p 127.0.0.1:9229:9229       │
                                                           ▼
                                           Node Inspector in container
                                              (--inspect=0.0.0.0:9229)
                                                           │
                                                           ▼
                                  Node.js process executes /app/app.js
                                                           │
Host HTTP request ───── -p 127.0.0.1:3000:3000 ────────────┤
                                                           ▼
                                               HTTP server on 3000
```

**3000 = application port.** You send requests to it.  
**9229 = debugger port.** VS Code uses it to inspect and control the Node process.

The ports are independent; you can serve HTTP without enabling a debugger. `podman -p` configures transport-level mapping, but cannot force Node to start an inspector. The Node process needs `--inspect` (or an equivalent programmatic debug configuration).

### Why `--inspect=0.0.0.0:9229` inside a container?

If the Node inspector listens only on `127.0.0.1` **inside** the container's own network namespace, the connection forwarded to the container's network interface may not reach it. Listening on `0.0.0.0` **inside** the container permits access via that container interface.

The corresponding **host** side must still bind only `127.0.0.1`: `-p 127.0.0.1:9229:9229`. This is a security boundary for a local practice setup, not a license to run inspectors on public production systems. Network-level controls, VM configuration and tunneling still matter.

## 3. How the Node inspector actually works

Node.js supports the Inspector Protocol, accessed through a WebSocket endpoint. When started with `--inspect`, Node prints a debugger WebSocket address, such as:

```text
Debugger listening on ws://0.0.0.0:9229/<generated-session-id>
```

The UUID varies; it is **not** a reusable hardcoded address. The debug client discovers/uses the inspector endpoint via the configured host and port. The debugger can:

- Set breakpoints on a source line.
- Pause the JavaScript execution thread at the breakpoint.
- Read parameters and local variables in the paused stack frame.
- Step over/into/out of code, inspect the call stack and resume execution.

The debugger is **not** the same as a plain HTTP browser connection; the WebSocket protocol carries debug commands and events.

### What happens when a breakpoint is hit?

For the included `app.js`:

```js
function calculateTotal(price, quantity) {
  const total = price * quantity;  // set breakpoint here
  return total;
}
```

When a request triggers `calculateTotal(250, 3)`, VS Code can pause *before* the multiplication statement executes. At that moment, `price` is `250`, `quantity` is `3`, and `total` is not yet initialized. After **Step Over**, `total` becomes `750`. If the request is waiting on that code path, the HTTP response waits until the debugger allows execution to continue.

**Step Over** executes the current line; **Step Into** follows an invoked function; **Step Out** executes to the current function's return; **Continue** resumes execution. This makes debugger sessions more useful than repeated guess-and-print iterations.

## 4. `launch.json`: the control plane of VS Code debugging

The instructor's configuration:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "node",
      "request": "attach",
      "name": "Attach to Container",
      "address": "localhost",
      "port": 9229,
      "localRoot": "${workspaceFolder}",
      "remoteRoot": "/app"
    }
  ]
}
```

| Property | Meaning | Common mistake |
| --- | --- | --- |
| `version` | VS Code launch schema version | Confusing with Node.js version |
| `type: node` | Node/JavaScript debug adapter | Selecting an unrelated runtime |
| `request: attach` | Connect to an existing process | Assuming attach will start a stopped app |
| `name` | Display label in Run and Debug | Treating it as container name |
| `address: localhost` | Host as seen by VS Code's debug adapter | Assuming Windows `localhost` is RHEL VM localhost |
| `port: 9229` | Inspector listening port reachable by IDE | Using app port `3000` here |
| `localRoot` | Source path open in VS Code | Opening unrelated workspace/file version |
| `remoteRoot: /app` | Path inside container where source lives | Forgetting bind-mount destination |

The filename `.vscode/launch.json` is IDE configuration, **not** a Podman or Docker configuration file. VS Code's built-in JavaScript debugger supports Node attach; the older separate Node debugger extension is usually unnecessary, and Dev Containers is not a requirement for basic TCP attach.

### Why source mapping matters

The process reports that the executing file is `/app/app.js`. VS Code may have it open as:

```text
/home/learner/remote-debug-lab/app.js
```

Or as a Windows file path. Mapping says these represent the same source. Without proper mapping, attaching to the inspector can succeed while the red breakpoint remains unverified (hollow) and never pauses.

If your VS Code workspace source differs from the code executing in the container, breakpoints may hit surprising locations or fail. Use the identical source tree and keep its paths consistent.

## 5. Container image versus source bind mount

This repository contains both a `Containerfile` and `app.js`.

```dockerfile
FROM docker.io/library/node:22-alpine
WORKDIR /app
COPY app.js /app/app.js
EXPOSE 3000 9229
CMD ["node", "--inspect=0.0.0.0:9229", "app.js"]
```

- `FROM`: runtime environment with Node installed.
- `WORKDIR`: sets the process working directory.
- `COPY`: embeds a snapshot of the sample code during image build.
- `EXPOSE`: documents intended ports in image metadata; it does not publish them to the host and does not activate inspector.
- `CMD`: starts the process in inspector mode and runs the application.

**Task 1 without bind mount:** container reads embedded `/app/app.js`. Changes to your host `app.js` require a rebuild/redeployment if you want the updated code inside the image.

**Task 2 with bind mount:** `-v "$(pwd):/app:Z"` places the host directory at `/app`, hiding the embedded `/app` files at that path while mounted. Source edits are visible instantly as file changes. However, Node normally loads JavaScript into a running process; file visibility does not equal live runtime reload. The running process must restart or use development watch mode if the edited module isn't dynamically reloaded.

**Common failure:** Running Task 2 from the wrong host folder overlays `/app` with a folder that lacks `app.js`. Node exits with a module-not-found error even though the image built successfully.

## 6. Why instructor Task 1 and Task 2 may conflict

Both original task commands name their container `debug-container`:

```bash
podman run -d -p 3000:3000 -p 9229:9229 --name debug-container my-node-app
podman run -d -p 3000:3000 -p 9229:9229 -v $(pwd):/app --name debug-container my-node-app
```

`podman stop debug-container` stops the process but **does not release the name**. To replace it in this disposable lab:

```bash
podman stop debug-container
podman rm debug-container
```

Then start the mounted version, ideally with `-p 127.0.0.1:...` and `:Z` on RHEL. Do not remove unrelated containers or use global delete commands to fix a name conflict.

## 7. SELinux, UID/GID and host ownership

On RHEL with SELinux enforcing, a bind mount can be denied even when ordinary UNIX permissions look correct. `:Z` asks Podman to relabel that host directory for **private container use**. `:z` is for content shared with multiple containers using compatible shared labels; neither option solves every Unix ownership problem.

Rootless Podman may use UID/GID mappings. Files writable by your RHEL user are not always writable by whichever user the container runs as. Distinguish permission-bit failures from SELinux AVC denials rather than applying broad recursive `chmod 777` or uncontrolled `chown` commands.

**Important:** Do not apply `:Z` to your whole home directory, system paths or shared repositories; it can affect access outside this container. Use a dedicated sample lab folder.

## 8. Windows VS Code ↔ RHEL VirtualBox VM: what “localhost” means

Each operating environment has its own loopback interface:

```text
Windows VS Code: localhost:9229  ≠  RHEL VM: localhost:9229
```

Publishing on RHEL's localhost does not automatically put the same port on Windows' localhost. A securely configured **SSH local port forward** is a common solution (only when the VM has SSH access):

```text
Windows command:
ssh -N -L 9229:127.0.0.1:9229 USER@RHEL_VM_IP
```

Then Windows VS Code can target Windows localhost `9229`, and the tunnel forwards it to RHEL's localhost `9229`. The app itself can be tested inside RHEL at `localhost:3000`. For correct breakpoints, the VS Code workspace must still reference matching source code (e.g. use Remote-SSH to work in the RHEL filesystem, or open a synchronized identical source tree).

An SSH tunnel changes connectivity, **not** source file synchronization. SSH host access must be configured and reachable; VirtualBox NAT may require host-only/bridged networking or appropriate port forwarding for SSH. Never publicly expose inspector merely to bypass network setup.

## 9. How remote debugging compares to production observability

**Lab environment:**

```text
VS Code → Node Inspector → pause application and inspect variables
```

**Typical AWS ECS/Fargate production workflow:**

```text
Alarm / user report → CloudWatch logs and metrics
→ application tracing / request IDs → ECS Exec where authorized
→ reproduce in an isolated environment → debug locally/staging
→ commit, test, deploy, monitor results
```

A debugger is powerful but can stop a process or expose secrets. Production workloads generally use:

- Centralized, structured logs for error context and request identifiers.
- Metrics and alerting to detect degradation (latency, memory, error rates).
- Traces to follow requests across services.
- Controlled runtime inspection, e.g. ECS Exec, when permissions and service configuration allow it.
- Safe reproduction in a development or staging environment, then code changes through reviewed deployment workflows.

A remote live production debugger is an exceptional, carefully authorized technique—not the normal first troubleshooting step.

## 10. Diagnostic decision tree

```text
Container not running?
  └─ podman ps -a → podman logs → fix CMD/app or missing mounted app.js

Application not responding on 3000?
  └─ confirm Node listens on 0.0.0.0:3000 and host port mapping

Application works, VS Code won't attach?
  └─ confirm --inspect, inspector logs, host port 9229, VM connectivity

Debugger attached, breakpoint never hits?
  └─ invoke route/function, check localRoot↔remoteRoot, match source versions

Code changed, output didn't?
  └─ bind mount updated file but running Node didn't reload the module
```

Useful safe checks:

```bash
podman ps -a --filter name=debug-container
podman logs debug-container
podman port debug-container
podman inspect debug-container --format '{{json .Mounts}}'
podman exec debug-container ls -l /app
curl http://localhost:3000
```

### Failure case: `Error: Cannot find module '/app/app.js'`

Likely you mounted the wrong host folder or the file is named differently. Check `pwd` and `ls app.js` on the host, then recreate from the correct folder. Rebuilding the image alone will not help if the mount still hides the image's baked-in code.

### Failure case: `Error: listen EADDRINUSE: address already in use :::9229`

An inspector port may already be occupied inside that container/process context, or a different launch pattern started another inspector. Host port allocation errors have distinct Podman messages; inspect host port mapping and process state to distinguish them.

### Failure case: Attach times out from Windows

The VM's inspector may be listening correctly, but Windows is trying its own localhost. Use an authorized tunnel or appropriate VM network access. Keep the inspector endpoint private.

## 11. Security checklist

- **Never publicly publish inspector port 9229.** It can lead to arbitrary code execution in the debugged process.
- Use `127.0.0.1` host binding or a secure tunnel with access control.
- Keep debugging off for ordinary production workloads.
- Avoid inspecting credentials or logging sensitive variable values in shared recordings.
- Do not share access to debug endpoints with unauthorized users.
- Avoid relabeling sensitive host directories with SELinux mount options.
- Remove obsolete debug containers and disable the inspector after experimentation.

## 12. Review/interview questions and answers

1. **Is `-p 9229:9229` enough for debugging?** No. It publishes a port; the runtime must activate and listen on its inspector/debug port.
2. **Why use `--inspect=0.0.0.0:9229`?** To let the container's inspector accept traffic forwarded via its container interface, while restricting the **host** port to localhost.
3. **Why does the debugger use a separate port from HTTP?** Different protocols and purposes: requests on 3000, inspector commands on 9229.
4. **What is remote debugging?** Controlling/inspecting an already running process from a separate debugger UI or environment.
5. **What is the difference between `attach` and `launch`?** Attach connects to an existing process; launch starts a new process under the debugger.
6. **Why do `localRoot` and `remoteRoot` exist?** To match IDE source locations to file locations reported by the runtime.
7. **Why might a breakpoint remain hollow?** Source-path/version mismatch, unbound breakpoint, or code path not executed.
8. **Does a bind mount rebuild the image?** No. It maps host files into the container runtime filesystem.
9. **Does modifying `app.js` change an already running Node process?** Not automatically; restart or use an appropriate watch/reload mechanism.
10. **Why can Task 2's run command fail after Task 1?** Both use the same `debug-container` name; stopping doesn't free the name.
11. **What does `:Z` do on RHEL?** Requests a private SELinux label for the mounted content; must be used selectively.
12. **Why is Windows `localhost` different from VM `localhost`?** They have separate network stacks; tunnel or network forwarding is required.
13. **Should you expose Node inspector on a public host?** No—treat it as a privileged code-execution interface.
14. **How would you investigate a faulty AWS ECS service?** Start with logs, metrics, traces and safe operational diagnostics; reproduce/debug in isolated staging where possible.
15. **What happens to an HTTP request during a breakpoint?** If its JavaScript execution path is paused, the request may wait until resumed.
16. **Can you use Python or Java instead?** Yes, but each has its own debugger agent, protocol and port; Node's launch configuration won't attach to them.
17. **Can source be inspected inside a running container without VS Code?** Yes, `podman exec ... cat/ls` inspects files, but it doesn't provide interactive language-level stepping.
18. **What evidence best demonstrates Task 3?** A breakpoint hit, visible variables, correct file mapping, and the request completing after execution resumes.

## 13. Production-oriented extension exercises (optional; not part of instructor tasks)

1. Add a test for `calculateTotal` and a CI job that runs it.
2. Demonstrate that a bind-mounted edit is visible under `/app`, but is not executed until Node restarts.
3. Break source-path mapping intentionally; troubleshoot a hollow breakpoint.
4. Use an authorized SSH tunnel to attach across the Windows/RHEL VM boundary.
5. Compare a local debugger session with a logs/metrics approach to the same app malfunction.

**Summary:** The fundamental engineering skill is separating **source-code visibility**, **process execution**, **debug transport reachability**, and **IDE source mapping**. Each can succeed or fail independently.
