# Lab 15 — Remote Debugging of Containers

**Track:** Domain 5 → Linux and Open Source → Red Hat 1  
**Status:** Completed — self-reported by learner  
**Focus:** Podman · Node.js Inspector · source bind mounts · VS Code attach debugging  
**Companion:** [Engineering Deep Dive](DEEP-DIVE.md)

> **Evidence integrity:** The learner reports completing this lab. This repository contains reproducible **reference** sources and instructions, not an independently verified session transcript or screenshots. The small Node.js application and `Containerfile` here are a runnable learning sample; they are not claimed to be the exact files from the learner's original execution.

## Learning objectives

By the end of the lab, you can:

1. Enable a language-specific debugger and publish its port through Podman.
2. Mount host source into a container for immediate file visibility without rebuilding the image.
3. Attach VS Code to a **running** Node.js process, hit a breakpoint, and inspect variables.
4. Differentiate application ports, debug ports, source mapping, and runtime restarts.

## Prerequisites

- RHEL/Fedora/Linux or WSL2; Podman/Docker installed; sufficient privileges to run rootless containers.
- VS Code on the same host or a securely connected workstation.
- Node.js debugging support in VS Code (the built-in JavaScript debugger suffices for Node.js attach).
- Instructor lists **Remote - Containers**, now commonly called **Dev Containers**; it is useful for developing inside containers, but **not required** for TCP inspector attachment. The old separate “Debugger for Node.js” extension is generally unnecessary in recent VS Code versions.
- The lab's `my-node-app` image name is a **placeholder** unless you build the image. This repo includes a `Containerfile` and a small `app.js` to make it reproducible.

## Files in this lab

```text
lab-15-remote-debugging-of-containers/
├── README.md
├── DEEP-DIVE.md
├── Containerfile
├── app.js
└── .vscode/
    └── launch.json
```

## Prepare once — build the example image

Open a terminal **in this lab folder**. On an RHEL VirtualBox VM, these commands run **inside RHEL**, not in Windows PowerShell.

```bash
podman --version
pwd
ls -l app.js Containerfile
podman build -t my-node-app -f Containerfile .
podman images my-node-app
```

The included application uses Node.js built-in `http`, listens on **port 3000**, and contains `calculateTotal(250, 3)`, which returns `750`. The image starts Node with `--inspect=0.0.0.0:9229`, enabling its inspector inside the container. `EXPOSE` alone would not start a debugger nor publish a host port.

> **Security warning:** The original instructor examples publish ports on all host interfaces. The commands are preserved below for traceability, but for actual testing **bind both host ports to `127.0.0.1`**. Node's inspector can provide code-execution capabilities. Never expose port 9229 to the Internet or an untrusted network. Use an SSH tunnel when attaching across machines.

---

## Task 1 — Expose debug ports

### Subtask 1.1 — Identify the language debugger port

| Runtime | Typical debugger/agent port | Activation example |
| --- | --- | --- |
| Node.js | `9229` | `node --inspect=0.0.0.0:9229 app.js` |
| Python | `5678` | `python -m debugpy --listen 0.0.0.0:5678 app.py` (requires `debugpy`) |
| Java | `5005` | JDWP configuration, such as `-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005` (JDK/runtime dependent) |

**Principle:** Publishing a port does **not** activate a debugger. An appropriate debugger must actually listen in the process.

### Subtask 1.2 — Run a container with the debug port exposed

**Instructor's exact command** (preserved, but do not use unprotected on a shared machine):

```bash
podman run -d -p 3000:3000 -p 9229:9229 --name debug-container my-node-app
```

**Safer command for local practice** (same container/debug ports, host localhost binding):

```bash
podman run -d \
  --name debug-container \
  -p 127.0.0.1:3000:3000 \
  -p 127.0.0.1:9229:9229 \
  my-node-app
```

The `my-node-app` image must have been built in **Prepare once**. Otherwise Podman will try to resolve/pull it and may fail.

**Verify:**

```bash
podman ps --filter name=debug-container
podman logs debug-container
curl http://localhost:3000
curl http://localhost:3000/health
```

Expected for the **provided sample**, not a captured historical output:

```text
Total: 750
OK
```

Logs should contain a `Debugger listening on ws://...:9229/...` message and `Lab 15 sample app listening on port 3000`.

**Instructor troubleshooting:** If the host port `9229` is occupied, map another **host** port to container port `9229`, e.g. `-p 127.0.0.1:9230:9229`. Then set `"port": 9230` in VS Code's `launch.json`.

---

## Task 2 — Mount source code for live debugging

### Subtask 2.1 — Run a container with a bind mount

**Instructor's exact command:**

```bash
podman run -d -p 3000:3000 -p 9229:9229 -v $(pwd):/app --name debug-container my-node-app
```

**Important:** This is **another** `podman run` using the same `--name debug-container`. You cannot run both Task 1 and Task 2 commands successively without removing the prior container; `podman stop` alone leaves the name reserved.

If Task 1's `debug-container` exists, stop and remove **only this lab's container**:

```bash
podman stop debug-container
podman rm debug-container
```

From the folder containing `app.js`, use this **RHEL-safe, localhost-only** variant:

```bash
podman run -d \
  --name debug-container \
  -p 127.0.0.1:3000:3000 \
  -p 127.0.0.1:9229:9229 \
  -v "$(pwd):/app:Z" \
  my-node-app
```

- `$(pwd)` expands to the current **host** directory; `:/app` is the **container** path.
- `:Z` requests a private SELinux label appropriate for RHEL when SELinux is enforcing. Only relabel a dedicated lab directory you control; do not relabel arbitrary shared/source directories.
- Because the `Containerfile` sets `WORKDIR /app`, its entry command sees the mounted `app.js` at `/app/app.js`.
- A bind mount at `/app` hides image-baked `/app` files while the mount is active; this is why the host directory must actually contain the app.

### Subtask 2.2 — Verify mounted files

**Instructor's exact command:**

```bash
podman exec -it debug-container ls /app
```

Expected: `app.js` and other files of the current host folder are visible.

**Additional checks:**

```bash
podman exec debug-container cat /app/app.js
podman inspect debug-container --format '{{json .Mounts}}'
curl http://localhost:3000
```

**Important subtlety:** Editing a file on the host updates the mounted file immediately, but a running `node app.js` process **does not automatically reload code**. Restart the process/container or run an appropriate development watch mode to execute the changed code.

---

## Task 3 — Connect the IDE debugger to the container

### Subtask 3.1 — VS Code debugging tools

1. Install/open **Visual Studio Code**.
2. Instructor: install the **Remote - Containers** extension (now **Dev Containers**) and **Debugger for Node.js**. Current VS Code generally has Node.js JavaScript debugging built in; extension installation is not necessarily required for this attach workflow.
3. Open this **lab directory** as the VS Code workspace so `${workspaceFolder}` points to the local source folder that corresponds to container `/app`.

### Subtask 3.2 — Attach to the running container

1. Start the container from Task 2, confirm `podman ps` and the debugger log.
2. Open **Run and Debug** (typically `Ctrl+Shift+D`).
3. Select **create a `launch.json` file** → **Node.js** if prompted; this repository already contains [`.vscode/launch.json`](.vscode/launch.json).
4. **Instructor's exact configuration**, saved in `.vscode/launch.json`:

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

5. In VS Code, open `app.js` and click the gutter beside `const total = price * quantity;` to set a **breakpoint**.
6. Choose **Attach to Container** and start debugging using **F5** / the green play icon.
7. From a terminal on the **Podman host**, send an HTTP request to reach the function:

   ```bash
   curl http://localhost:3000
   ```

8. When VS Code pauses at the breakpoint, inspect `price = 250` and `quantity = 3`; then **Step Over (F10)** and inspect `total = 750`. Continue (**F5**) to allow the HTTP response to finish.

**What `launch.json` means:** `request: attach` connects to a process already running. `port: 9229` targets the Node inspector. `localRoot` maps VS Code source files to the container's `remoteRoot: /app`. This lets source breakpoints resolve correctly.

### VS Code on Windows + Podman inside a RHEL VirtualBox VM

The instructor's `"address": "localhost"` means **localhost of the VS Code/debug adapter environment**. Windows localhost is **not** the same as a separate RHEL VM's localhost.

Options:

- **Easiest conceptually:** Run VS Code in the RHEL environment where Podman is running and open the same source directory. Attach to local port `9229`.
- **Remote workstation:** Use a secured SSH connection/tunnel or suitable VM forwarding rather than exposing inspector publicly. Example **if SSH access is configured and reachable**: on Windows run `ssh -N -L 9229:127.0.0.1:9229 USER@RHEL_VM_IP`. Keep the container port bound to RHEL's `127.0.0.1`. Open the matching source code on Windows or through VS Code Remote-SSH; ensure `localRoot` maps to those files. Then attach to Windows `localhost:9229`.

If the VM is NAT-only without reachable SSH, configure authorized VM host-only/bridged access or NAT SSH port forwarding first. Do **not** make the debugger world-accessible as a shortcut.

### Expected result vs proof

The expected demonstration is VS Code attached to the running process, a **verified breakpoint hit**, variables visible, and the web response completing after continuing. The learner reports the lab completed; screenshots, a launch transcript, or independent debugger verification are **not provided in this repository**.

---

## Troubleshooting matrix

| Symptom | Likely cause | Check / correction |
| --- | --- | --- |
| `my-node-app` not found | Instructor placeholder not built | `podman build -t my-node-app -f Containerfile .` |
| Container name already in use | Task 1's container still exists | Stop and remove **that exact lab container** before Task 2 |
| Port already allocated | Another process/container uses `3000` or `9229` | `ss -ltnp \| grep -E ':(3000\|9229)'`; change **host** port and VS Code config accordingly |
| Container exits | JS missing/invalid; startup failure | `podman ps -a`; `podman logs debug-container` |
| `/app` is empty | Wrong current directory mounted | `pwd`, `ls -l app.js`, `podman inspect ...`; recreate from lab directory |
| Permission denied on RHEL | SELinux context or rootless permissions | Use dedicated directory with `:Z`; inspect actual error; do not blindly `chmod -R 777` |
| Web endpoint works, debugger refuses | `--inspect` missing or wrong address/port | Read `podman logs`; `podman port debug-container`; validate VS Code config |
| Attach succeeds but breakpoint is hollow | Source path mismatch | Verify `localRoot`, `remoteRoot`, VS Code workspace and the same file version |
| Windows VS Code cannot attach to RHEL VM | `localhost` points to the wrong OS | Secure SSH tunnel / VS Code Remote-SSH / VM forwarding |
| Changed source does not change HTTP output | Source is mounted but Node process not restarted | Restart application or enable safe development watch mode |
| Browser hangs while debugging | Request was paused at a breakpoint | Continue execution in VS Code |

**Extra diagnostic commands:**

```bash
podman ps -a --filter name=debug-container
podman logs debug-container
podman port debug-container
podman exec debug-container ls -l /app
curl http://localhost:3000/health
```

## Security and safe cleanup

- Node's inspector should never be exposed to untrusted networks. Avoid `-p 9229:9229` on public or shared hosts.
- Keep debugger off in production images/workloads unless a carefully authorized, time-limited diagnostic procedure requires it.
- Treat inspected variables as potentially sensitive.
- Stop/remove **only this** lab container; the image and source files may be reused:

```bash
podman stop debug-container
podman rm debug-container
```

Optional, only when no longer needed:

```bash
podman rmi my-node-app
```

## Completion and evidence checklist

- [x] Task 1: Debug-port concepts and published-port container — learner confirmed completion.
- [x] Task 2: Source bind mount and file verification — learner confirmed completion.
- [x] Task 3: IDE attach workflow — learner confirmed completion.
- [ ] Original terminal logs/screenshots attached as independent evidence (not provided).
- [ ] CI validation of this learning sample (not included; no claims of passing CI).

**Interview recap:** A published port does not activate the debugger; source mounts do not auto-reload a process; a remote IDE needs network reachability **and** correct source path mapping.

**Next:** [Deep Dive — Container Debugging Internals](DEEP-DIVE.md) · [All Red Hat 1 Labs](../LABS-INDEX.md)
