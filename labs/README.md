# Lab 08 — EXPOSE & Port Binding | Podman Engineering Journal

**Domain 5 → Linux & Open Source → Red Hat 1 → Topic 2: Red Hat Certified Specialist in Containers**  
**Lab evidence captured:** 25 October 2026  
**Environment:** Al Nafi Ubuntu lab terminal, Podman, Python/Flask  
**Skills:** Container networking · `EXPOSE` · `-p` and `-P` · TCP connectivity · port-conflict diagnosis · reproducible verification  
**Evidence status:** **Partial but genuine.** The screenshots establish successful build/publishing and access through host port **9090**. A simulated *occupied-port* failure and dynamic `-P` test are documented as reproducible exercises, **not as independently verified results**.

> **Engineering insight:** A service can be listening perfectly inside a container and still be unreachable from the host. The application listening address, container port, Podman host-port publishing and the caller's network location are separate layers of one connectivity problem.

**[Read the Deep Dive](DEEP-DIVE.md)** · **[Reproduce the lab](#reproduce-the-four-tasks)** · **[Inspect genuine evidence](#genuine-execution-evidence)** · **[Troubleshoot networking](#troubleshooting-runbook)**

---

## 1. Engineering problem

A developer has a Python service running on TCP port `8080` *inside* a container. A browser, monitoring probe, or another host process needs to reach it. How can we make the service reachable without confusing an **image instruction** with an **actual network binding**? How do we prove that the path works? And what happens when two containers try to publish the same host port?

This lab builds a small Flask service and uses Podman to walk through those questions. The objective is not to claim production web-server engineering: it is to master the networking fundamentals that reliable container deployments depend on.

### What was exercised and what was observed

| Lab objective | Evidence-backed observation | Status |
|---|---|---|
| Task 1 — Flask app + `EXPOSE 8080` | Build output includes `EXPOSE 8080` and container image successfully tagged | **Observed** |
| Task 2 — Publish port `8080:8080` | `podman ps` shows `webapp` running and `0.0.0.0:8080->8080/tcp` | **Observed** |
| Task 3 — Switch publishing to `9090:8080` | `webapp2` running; `curl localhost:8080` fails after old mapping is absent, while `curl localhost:9090` returns expected text | **Observed** |
| Task 4 — Deliberate occupied-port conflict, resolve, `-P` | The course lists the task, but the supplied screenshots do **not** show conflict output, resolution, or `-P` output | **Procedure provided; not independently evidenced** |

**Recorded outcome:** `Hello from the exposed container port!` was returned successfully via **host port 9090**. This establishes a working request path from the lab host to the Flask app running on container port 8080. It does not establish public internet accessibility or production readiness.

---

## 2. Mental model — one minute

```text
Host process / curl
  |
  | http://localhost:9090
  v
HOST TCP PORT 9090    <-- opened by -p 9090:8080
  |
  | Podman host-to-container port forwarding
  v
CONTAINER TCP PORT 8080
  |
  v
Flask app listens on 0.0.0.0:8080 inside container
  |
  v
HTTP 200 + "Hello from the exposed container port!"
```

`EXPOSE 8080` in the Containerfile **documents the intended container-side port**; it does not open a host port by itself. The port publication comes from `podman run -p HOST_PORT:CONTAINER_PORT`, while `-P` publishes exposed ports to dynamically assigned host ports.

In `-p 9090:8080`, **9090 is on the host** and **8080 is inside the container**. Changing the host port does *not* change Flask's internal listening port.

---

## 3. Repository contents

```text
lab-08-expose-and-port-binding/
├── README.md                           # Recruiter-facing technical case study + every task
├── DEEP-DIVE.md                        # Foundations, packet journey, security, diagnosis, Q&A
├── Containerfile                       # Reproducible teaching image
├── app.py                              # Working Flask example
├── requirements.txt                    # Python dependency declaration
├── .containerignore                    # Prevents pushing unrelated build context into image
├── tests/
│   └── smoke-test.sh                   # Optional host-side HTTP response assertion
└── evidence/
    ├── 01-build-and-8080-port-mapping.png
    └── 02-9090-port-mapping-and-curl.png
```

**Reconstruction note:** `Containerfile`, `app.py`, `requirements.txt`, and the optional test are clean, newly authored reproductions based on the shared lab material and previously discussed steps. They were **not exported byte-for-byte from the timed training VM**. Do not present the included test script as something already executed during the screenshot session.

---

## 4. Reproduce the four tasks

### Prerequisites and workspace

Podman must work on Linux (rootless is preferred for a learning environment), image registry access must be available, and `curl` must be present on the host. `ss` and `lsof` are optional diagnostic tools.

```bash
podman --version
mkdir -p ~/port-binding-lab
cd ~/port-binding-lab
# Copy the files in this repository into the directory, or clone the repository.
ls -la
```

Run the subsequent commands from the directory containing `Containerfile`.

### Task 1 — Write a service and document its port

**Subtask 1.1 — `app.py`:** The Flask route at `/` returns a short text response. `host="0.0.0.0"` is crucial: inside the container it asks Flask to bind all *container network interfaces*. Binding only `127.0.0.1` inside the container can prevent host-to-container forwarding from reaching the application.

The relevant application lines are:

```python
@app.get("/")
def hello():
    return "Hello from the exposed container port!\n"

app.run(host="0.0.0.0", port=8080)
```

**Subtask 1.2 — `requirements.txt` and Containerfile:** `Flask>=3.1,<4` describes the Python dependency; the `Containerfile` installs it, copies the source and sets `EXPOSE 8080/tcp` plus `CMD ["python", "app.py"]`.

```dockerfile
FROM docker.io/library/python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 8080/tcp
CMD ["python", "app.py"]
```

**Why this order?** Separating the requirements copy from application code can preserve the dependency-installation cache when only app code changes. `.containerignore` keeps screenshots, docs, virtual environments and secrets out of build context.

Inspect the exposed-port metadata after building:

```bash
podman image inspect exposed-app --format '{{json .Config.ExposedPorts}}'
```

**Expected concept:** an `8080/tcp` entry in metadata; this is *not* evidence of host accessibility.

### Task 2 — Build the image and publish port 8080

**Subtask 2.1:**

```bash
podman build -t exposed-app .
```

**Subtask 2.2:**

```bash
podman run -d --name webapp -p 8080:8080 exposed-app
podman ps
podman port webapp
```

The screenshot from the training lab shows a successful image build and a running `webapp` with `0.0.0.0:8080->8080/tcp`. The container ID itself is not essential to the lesson.

**Interpretation:** Host port `8080` has been published and forwards to the container's port `8080`. Whether a remote machine can reach that host port additionally depends on binding address, firewalls and platform network access.

### Task 3 — Test access and change host port

**Subtask 3.1 — Test first mapping:**

```bash
podman port webapp
ss -tulnp | grep ':8080' || true
curl -v http://127.0.0.1:8080/
sh tests/smoke-test.sh 8080
```

The screenshot set does **not** independently show the successful `curl 8080` response while `webapp` was running. It *does* show the port advertised by Podman. The commands above are supplied to verify the complete HTTP path when reproducing the lab.

**Subtask 3.2 — Map a different host port:**

```bash
podman stop webapp
podman rm webapp
podman run -d --name webapp2 -p 9090:8080 exposed-app
podman ps
curl -v http://127.0.0.1:9090/
sh tests/smoke-test.sh 9090
```

**Evidence-backed response:**

```text
Hello from the exposed container port!
```

The training screenshot also shows that a call to `localhost:8080` failed after the first publication was no longer active. **That error is expected**, because only `9090` was published for `webapp2` at that point; it does not indicate an unhealthy Flask app.

### Task 4 — Diagnose an occupied host port (guided reproduction)

**Subtask 4.1 — Correctly simulate a conflict:** The original worksheet attempts another bind on `8080` *after stopping the container previously owning that port*. That may not produce any conflict. Instead, keep `webapp2` running on **host port 9090**, then attempt to publish the *same host port* for a second container:

```bash
# While webapp2 is running with 9090:8080:
podman run -d --name webapp-conflict -p 9090:8080 exposed-app
```

**Expected if 9090 is occupied:** Podman refuses to publish the second container on that host port. Actual error wording depends on Podman/backend. **No screenshot of this failure was supplied**.

**Subtask 4.2 — Investigate and resolve:**

```bash
podman ps --format '{{.Names}}  {{.Ports}}'
podman port webapp2
ss -tulnp | grep ':9090' || true
sudo lsof -nP -iTCP:9090 -sTCP:LISTEN  # only if lsof is installed

# Remove a failed container if Podman left one behind:
podman rm -f webapp-conflict 2>/dev/null || true

# Preserve webapp2; choose an unused host port instead:
podman run -d --name webapp-alt -p 127.0.0.1:9091:8080 exposed-app
curl http://127.0.0.1:9091/
```

**Alternative — automatic host-port assignment** (`-P` uses exposed port metadata):

```bash
podman run -d --name webapp-auto -P exposed-app
podman port webapp-auto
```

Read the actual dynamically assigned host port from `podman port`; never assume it will be a specific number. `-P` is a different mode from `-p 9090:8080`.

---

## 5. Genuine execution evidence

### Evidence 01 — Build and first port mapping

![Real terminal proof: exposed-app built and webapp running with port 8080 mapped](evidence/01-build-and-8080-port-mapping.png)

**Observed:** `EXPOSE 8080`, successful image tag, `podman run -d -p 8080:8080 --name webapp ...`, and `podman ps` with host port forwarding. This screenshot does not include a successful `curl` test.

### Evidence 02 — Changed host port and successful HTTP response

![Real terminal proof: webapp2 mapped from 9090 to 8080, curl to 9090 succeeded](evidence/02-9090-port-mapping-and-curl.png)

**Observed:** `webapp2` binds `0.0.0.0:9090->8080/tcp`, host-port 8080 is no longer reachable, and `curl http://localhost:9090` returns the expected Flask message. The failed `curl :8080` is meaningful diagnostic evidence, not something to hide.

**Image authenticity:** The screenshots were enlarged and lightly sharpened for readability; terminal output and technical claims have not been redrawn, fabricated or edited. Only the original screenshot frames were available; no additional terminal proof was invented.

---

## 6. Troubleshooting runbook

| Symptom | Investigation | Likely fix |
|---|---|---|
| Build fails pulling image | `podman pull docker.io/library/python:3.12-slim` | Registry/network connectivity, proxy, rate limits |
| Python cannot import Flask | `podman logs webapp2` | Ensure dependencies installed, rebuild with correct context |
| Container exits immediately | `podman ps -a`, `podman logs webapp2` | Fix Python error or startup command |
| `curl localhost:8080` fails after remap | `podman ps`, `podman port webapp2` | Use the *current* published port `9090` |
| Cannot bind host port | `podman ps`, `ss -tulnp`, optional `lsof` | Stop owner if appropriate or choose another host port |
| Published port exists but no HTTP response | `podman logs`, `podman exec ... ss -tln` (tool permitting) | Ensure application listens on `0.0.0.0:8080` |
| Works on host, fails from laptop | Check where `localhost` refers; inspect host IP, firewall, NAT | Connect to the actual VM/lab host when allowed; configure access safely |
| `-P` gives unexpected host port | `podman port webapp-auto` | Use discovered dynamic port; do not hardcode |

### Efficient diagnosis order

1. **Process:** Is the container actually running? `podman ps -a`.
2. **Logs:** Is Flask listening, crashing or failing imports? `podman logs <name>`.
3. **Metadata / mapping:** What port was actually published? `podman port <name>`.
4. **Host HTTP:** Does `curl -v http://127.0.0.1:<host-port>/` succeed?
5. **Remote path:** If applicable, investigate remote IP, firewalls, security groups, VM NAT and routing *after* local checks pass.

Avoid reflexively running containers with `--privileged` to fix ordinary port-mapping problems. It weakens isolation and is not needed for this lab.

---

## 7. Cleanup — targeted and safe

The worksheet suggests `podman stop -a && podman rm -a`. That stops/removes **every** container in the current Podman store, including unrelated labs. Use a targeted cleanup instead:

```bash
podman rm -f webapp webapp2 webapp-conflict webapp-alt webapp-auto 2>/dev/null || true
# Optional: remove just the image created for this lab:
podman rmi exposed-app
```

Do not delete evidence or project source files after cleanup.

---

## 8. Engineering lessons and next iterations

- **Document != publish:** `EXPOSE` advertises an intended container port; `-p` actually publishes it.
- **Host and container port are independent:** `9090:8080` does not require changing Flask code.
- **Validate at the right layer:** `podman ps` proves reported state, whereas a successful `curl` verifies the HTTP path.
- **Errors carry context:** `8080` failed after removing its mapping; `9090` succeeded and proved the updated mapping.
- **Network exposure should be intentional:** Publishing on all host interfaces may expose a service beyond localhost. Use `127.0.0.1:HOST:CONTAINER` for local-only development when appropriate.
- **Evidence integrity matters:** Task 4 is a documented next experiment, not a verified incident in this archive.

### Improvement backlog

- Capture an explicit **port-in-use failure** and its remediation as new genuine evidence.
- Compare `-p 127.0.0.1:9090:8080` against binding all host interfaces.
- Add an HTTP health endpoint and basic host-side smoke test to CI.
- Replace Flask's development server with a production-suitable WSGI server *in a separate application project*.
- Pin base-image digests and lock dependency versions when strict reproducibility is required.

### References

- [Podman `run` — `--publish` and `--publish-all`](https://docs.podman.io/en/stable/markdown/podman-run.1.html)
- [Podman `build` — Containerfile and build contexts](https://docs.podman.io/en/latest/markdown/podman-build.1.html)
- [Docker reference — publishing versus exposing ports](https://docs.docker.com/engine/containers/run/)

For beginner explanations, packet flow, interview questions, security considerations and networking failure analysis, continue to **[DEEP-DIVE.md](DEEP-DIVE.md)**.
