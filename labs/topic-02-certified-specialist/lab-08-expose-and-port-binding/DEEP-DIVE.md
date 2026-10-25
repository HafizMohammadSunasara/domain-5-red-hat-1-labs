# Engineering Deep Dive — EXPOSE, Port Publishing, and Network Diagnostics

**Lab 08 | Domain 5 · Red Hat 1 · Topic 2: Container Engineering**  
**Case:** Flask inside Podman, service port `8080`, published host ports `8080` and `9090`  
**Audience:** Complete beginners, junior Cloud/DevOps engineers, and interview preparation  
**Reality check:** Concepts and runnable examples are educational; observed evidence comes only from the two genuine terminal screenshots in [`evidence/`](evidence/). Task 4's port-in-use error was **not independently captured**.

> **North-star question:** When a container is running but nobody can reach the application, which layer is failing: the process, the listening socket, the container network, the host mapping, or an outside firewall?

**[Back to practical README](README.md)** | [See complete evidence](README.md#genuine-execution-evidence) | [Run automated smoke check](tests/smoke-test.sh)

---

## 01. Why this lab matters in engineering

Container networking is often taught as a single flag, `-p`, but diagnosing outages requires understanding several independent systems. A container runtime can report **Running** while a Python process is crashing. A Python process can be healthy while listening only to loopback. Podman can have a correct mapping while the user's curl request goes to the wrong machine. A host port can be occupied by a different process, even if the container's internal port is free.

This lab deliberately isolates those systems with a tiny Flask application. The simplicity is an advantage: when a request fails, we can avoid blaming application business logic and focus on the transport path.

### What a successful test actually proves

If a command executed **on the Podman host** returns the expected body from `curl http://127.0.0.1:9090`, it proves that, at that moment, a listening HTTP service was reachable along that local host-to-container path. It does **not** establish that the service was reachable from the public Internet, secured with TLS, deployed across multiple hosts, or ready for production traffic. Good engineers match the breadth of their claims to the breadth of their tests.

---

## 02. Start at zero: process, socket, IP address, port

**Process:** A running program. In our container it is `python app.py` serving a Flask web application.

**Socket:** An endpoint for communication. For TCP, a listening socket is associated with a transport protocol, local IP address and local port.

**IP address:** Identifies an interface or destination within a network. Examples are `127.0.0.1`, a container-assigned IP and the IP of the VM hosting Podman.

**Port:** A numbered transport-layer endpoint, such as TCP port `8080`. TCP and UDP have independent port spaces; TCP 8080 and UDP 8080 are not the same service.

**HTTP:** An application-layer protocol normally carried over TCP (or QUIC over UDP for HTTP/3). Flask in this lab uses HTTP over TCP. If TCP forwarding works but HTTP returns a server error, networking may be healthy while application behavior is not.

To send an HTTP request to `http://127.0.0.1:9090`, the client first needs a reachable TCP listener at **that machine's** port 9090. Only then can it send the HTTP request and receive a response.

---

## 03. Three different places a port exists

The most common beginner mistake is to treat the port in Python, the port in `EXPOSE` and the port in `podman run -p` as identical things. They are related, but they serve different purposes:

1. **Application listening port:** `app.run(host='0.0.0.0', port=8080)` opens port 8080 *inside the container network namespace*.
2. **Image documentation:** `EXPOSE 8080/tcp` records that the image expects a TCP listener on 8080. It does not open anything on the host.
3. **Host publication:** `podman run -p 9090:8080 ...` tells Podman to arrange traffic from the host-side TCP port 9090 to the container-side TCP port 8080.

You can change the host port without rebuilding the image. You must change the application configuration if you want the program to listen on a different **container** port. In most situations you would keep a stable internal application port and choose host ports based on deployment needs.

**Memorable analogy:** The app listens at Room 8080. `EXPOSE` is a label on the building plan saying the room exists. `-p 9090:8080` creates a reception desk numbered 9090 and forwards visitors to Room 8080. A label alone does not create the desk.

---

## 04. What `EXPOSE` really does, and what it does not

`EXPOSE` is a Containerfile/Dockerfile instruction that associates a port and protocol with an image. It is essentially configuration metadata. In the lab:

```dockerfile
EXPOSE 8080/tcp
```

You can inspect that intent:

```bash
podman image inspect exposed-app --format '{{json .Config.ExposedPorts}}'
```

A reasonable result includes `8080/tcp`. It says nothing about whether a Python process has started, whether a server is listening, whether port forwarding is enabled, or whether `curl` can reach it.

A container **can** serve a port without declaring `EXPOSE`, and explicit `-p` can still publish a working listening service. Conversely, declaring `EXPOSE` does not force any process to use the port. This explains why an image can advertise a perfectly sensible port and still serve nothing.

`EXPOSE` becomes operationally relevant to automatic publishing: `podman run -P` publishes the image's exposed ports to host ports chosen dynamically. It is also useful documentation for maintainers and tools that inspect image metadata.

---

## 05. Why Flask listens on `0.0.0.0`, not just localhost

Compare these two Python startup configurations:

```python
app.run(host='127.0.0.1', port=8080)
app.run(host='0.0.0.0', port=8080)
```

**Inside the container**, `127.0.0.1` means that container's own loopback interface. If the HTTP server listens only there, forwarding traffic to the container's network interface might not reach that socket.

`0.0.0.0` is an IPv4 *wildcard listening address*: it means accept connections sent to the available IPv4 interfaces, subject to the surrounding network configuration. It is not a remote URL you browse. When testing the host side, you still use `http://127.0.0.1:<published-port>` or the host's actual IP.

Notice that `0.0.0.0` appears in **two distinct contexts**:

- Flask inside the container: `0.0.0.0:8080` is its internal listening scope.
- `podman ps` on the host: `0.0.0.0:9090->8080/tcp` indicates the host published port is bound broadly, not only to a loopback address.

The same address string can describe separate network namespaces. It does not mean the container and host share the same interfaces.

---

## 06. Container networking and isolation, without jargon

A container normally has its own view of network interfaces, routes, addresses and ports, depending on its configured network mode. This view is called a **network namespace** on Linux. Network namespaces let two applications both listen on internal port 8080 without necessarily conflicting: they are not competing for the same listening socket inside a single shared namespace.

However, two independent containers cannot both publish onto the **same host IP, host port and protocol** at the same time. The conflict is on the host side. This is why `webapp` and `webapp2` can run applications internally on `8080` but must select different published host ports if both are active.

The precise forwarding implementation differs across rootful and rootless Podman versions and network backends. Some traffic paths use network address translation; rootless paths can use userspace forwarding components. For a beginner, the stable mental model is the same: incoming connections to an allowed host port are delivered to the intended container port.

---

## 07. Read the port mapping left to right

```bash
podman run -d --name webapp2 -p 9090:8080 exposed-app
```

Translate it into plain English: “Start a container named `webapp2`, run it detached, and publish **host TCP port 9090** so requests reach **container TCP port 8080**.”

- `podman run`: create and start a container from an image.
- `-d`: detached mode; CLI exits while the service stays active.
- `--name webapp2`: stable logical name for later `logs`, `port`, `stop`, `rm` and `inspect` commands.
- `-p 9090:8080`: network publication rule.
- `exposed-app`: image to run, built in Task 2.

The colon does not indicate “source port to destination port” for HTTP redirects. It is a transport-level forwarding configuration. The client still talks to the host port; it does not need to know the container's internal IP address.

You can write an explicit TCP suffix:

```bash
podman run -d --name local-only -p 127.0.0.1:9091:8080/tcp exposed-app
```

This publishes on the host's IPv4 loopback interface only, useful for local labs when remote access is not intended.

---

## 08. End-to-end traffic journey: `curl localhost:9090`

Here is the thought process of a packet-path investigator:

```text
(1) curl launched in Ubuntu VM / Podman host
      |
      | Resolve localhost => 127.0.0.1 (or ::1 if applicable)
      v
(2) Host TCP connection to port 9090
      |
      | Podman publication -p 9090:8080
      v
(3) Forwarding implementation to container's service port 8080
      |
      | Flask process bound to 0.0.0.0:8080 in container namespace
      v
(4) HTTP GET /
      |
      v
(5) Flask returns HTTP 200 and response body
      |
      v
(6) TCP reply travels back to curl on host
```

Each step has a validation command:

- Process: `podman ps --filter name=webapp2`.
- Container logs: `podman logs webapp2`.
- Forwarding: `podman port webapp2`.
- Host connectivity: `curl -v http://127.0.0.1:9090/`.
- Payload integrity: `sh tests/smoke-test.sh 9090`.

If the HTTP request succeeds, you have confirmed more than the mere existence of an image. You have reached the application through the route you intended.

---

## 09. `localhost` is relative to where you are standing

`localhost` does **not** mean “my app, wherever it is.” It means the machine or network namespace where the client program is running.

In your lab there can be three perspectives:

1. **Ubuntu lab VM terminal:** `localhost:9090` refers to the Ubuntu host running Podman. This is the context shown in the screenshots.
2. **Browser on the student's Windows laptop:** `localhost:9090` refers to the Windows laptop, not the remote Ubuntu lab VM.
3. **A shell inside the container:** `localhost:8080` refers to the container's local network view.

A curl success inside the Ubuntu VM does not guarantee that the Windows browser can reach the same address. Remote access may require an approved forwarded port, a reachable VM address, an SSH tunnel or provider-specific network configuration. In a training platform, avoid opening arbitrary services on public interfaces without permission.

**Troubleshooting rule:** Write down “client machine → address and port → target host → container port” before guessing what `localhost` points to.

---

## 10. Image construction, instruction by instruction

The provided Containerfile is intentionally simple:

```dockerfile
FROM docker.io/library/python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 8080/tcp
CMD ["python", "app.py"]
```

**`FROM`:** Chooses the Python runtime and a Debian-slim-style base. A tag like `3.12-slim` can change as the upstream image is updated; pinning a digest gives stricter repeatability.

**`WORKDIR`:** Future commands operate relative to `/app` unless specified otherwise. The directory is created if missing.

**`COPY requirements.txt .`:** Keeps dependency-definition changes distinct from source changes, improving layer-cache reuse when only the app is edited.

**`RUN pip install`:** Installs Flask into the image build. `--no-cache-dir` prevents pip from retaining its download cache in the resulting filesystem layer; it does not eliminate every possible image build cache.

**`COPY app.py .`:** Adds application code after dependency installation. For this sample we avoid a broad `COPY . .` because screenshots, secrets, and unrelated files should not enter the image.

**`EXPOSE 8080/tcp`:** Documents expected listening port; does not publish a host port.

**`CMD`:** Defines the default process when the image is run without a replacement command.

This is an educational image. Flask's development server is not designed to be a hardened production-facing HTTP service. For production you would consider a WSGI application server, proper health probes, least-privilege users, secrets handling, resource limits, immutably pinned dependencies and deployment-specific network policy.

---

## 11. What `podman build` produces, and what it does not

```bash
podman build -t exposed-app .
```

The `.` indicates the **build context**, the directory from which Podman can read files for `COPY` and related operations. If a referenced source file is not in the build context, the build can fail even though it exists elsewhere on disk. The `-t` flag attaches a human-readable local image name.

A successful build proves the instructions completed and an image was created. It does not prove the web server starts or that any network port is reachable. That requires **running** the image and performing a request test.

`podman images` answers “what images exist?” `podman ps` answers “what containers are running?” `curl` answers “did the HTTP request work at this endpoint?” They are complementary, not interchangeable.

---

## 12. What exactly does `podman ps` prove?

A `podman ps` row can show:

```text
webapp2 ... Up ... 0.0.0.0:9090->8080/tcp
```

This is excellent configuration evidence: the runtime reports a running container and a published host-port mapping. But it is not yet an application-layer verification. For example, you could publish `9090:8080` while the web app actually listens on 5000, or while it returns HTTP 500 errors.

`podman port webapp2` is often a clearer map than a wide `podman ps` table. `podman inspect` can answer additional questions about container configuration, image ID, network attachments and state. Use the smallest tool that answers the present question before dumping enormous JSON into the terminal.

---

## 13. What exactly does `curl` prove?

`curl http://127.0.0.1:9090/` checks real connectivity at the HTTP layer. With `-v`, curl also shows connection attempts, resolved addresses and response headers. With `-f`, it returns failure for many HTTP error status codes. With `--max-time`, it avoids hanging indefinitely when investigating faults.

To test the precise body, the included host-side script runs a response assertion:

```bash
sh tests/smoke-test.sh 9090
```

The command uses `curl --fail --silent --show-error --max-time 8`, then checks the text returned against a known expectation. A smoke test is intentionally small; it catches obvious deployment breakage but does not replace API contract tests, load tests, authentication testing or security scans.

If `curl` reports connection refused, investigate whether something is listening and whether forwarding exists. If it times out, routing or filtering might be involved. If it receives HTTP 404, connectivity likely succeeded but the URL path may be wrong. If it receives HTTP 500, the application handled the request but encountered a server-side error.

---

## 14. The actual 8080-to-9090 experiment

This lab's most important observation is not just “9090 worked.” It is the **contrast** between two moments:

1. The first screenshot shows `webapp` running with host port `8080` forwarding to container port `8080`.
2. The second screenshot shows `webapp2` running with host port `9090` forwarding to container port `8080`, a failed curl to **old host port 8080**, and a successful curl to **new host port 9090**.

That is exactly what reconfiguration should look like when the earlier publisher has been stopped/removed. The *container* still uses 8080. The *host* now directs callers to 9090. A failed request to 8080 after the change is not proof the application broke; it may be evidence that the stale endpoint was retired.

Professional post-change validation checks both the new endpoint works and the old endpoint behaves as expected. This principle scales from local containers to blue/green releases, load-balancer target swaps and API migrations.

---

## 15. The most subtle mistake in Task 4 of the worksheet

The worksheet proposes a port-conflict simulation on port 8080 after the workflow has already stopped the 8080 publisher and switched to port 9090. **A freed port is not occupied.** Merely attempting `-p 8080:8080` does not inherently create a collision.

For a deterministic demonstration, keep `webapp2` publishing port 9090 and attempt to publish 9090 again for `webapp-conflict`:

```bash
podman run -d --name webapp-conflict -p 9090:8080 exposed-app
```

Under ordinary conditions the second publication fails because the first mapping occupies the host port. The precise error text depends on environment and port-forwarding implementation. If the second container is partially created, remove it with `podman rm -f webapp-conflict` before reusing its name.

**Evidence discipline:** Your supplied screenshots do not capture this conflict. Therefore this document supplies the repeatable experiment without claiming that a specific conflict log was observed.

---

## 16. `ss`, `lsof`, and `podman port`: three lenses

`podman port webapp2` reports **Podman's known forwarding mappings**. For port-publishing investigations, it is often your most authoritative first stop.

`ss -tulnp | grep ':9090'` examines listening sockets as seen from the **host** network namespace. Depending on privileges, networking backend and user-space forwarding implementation, the process name may be absent or differ from expectation.

`sudo lsof -nP -iTCP:9090 -sTCP:LISTEN` asks which visible host process has the TCP listening socket. It is useful but optional, and it may not be preinstalled in minimalist training environments. It also cannot replace Podman's own description of how ports are published.

A command printing no output does not always mean “nothing is mapped.” Combine runtime metadata, host socket inspection and an actual request before drawing a conclusion. In short: observe from more than one layer.

---

## 17. `-p` versus `-P` — similar letters, different control

**Explicit publication `-p`:** You choose the host port and container port. Example: `-p 9090:8080`. This is predictable for scripts and local development, but can conflict with other services.

**Automatic publishing `-P`:** Podman publishes all exposed container ports using host ports selected dynamically. Example:

```bash
podman run -d --name webapp-auto -P exposed-app
podman port webapp-auto
```

Never assume the resulting host port will equal 8080, 9090 or any other fixed number. Discover it with `podman port`.

There is also `--expose` as a runtime metadata declaration in container tooling; like a Containerfile `EXPOSE` declaration, it should not be mistaken for host publication. Always distinguish “a port is documented” from “a port is reachable at a particular host address.”

---

## 18. Port security: broad bind or localhost only?

These are different security postures:

```bash
-p 9090:8080
-p 0.0.0.0:9090:8080
-p 127.0.0.1:9090:8080
```

Without an explicit host IP, Podman can bind broadly to host interfaces, depending on network settings and protocol support. An explicit `0.0.0.0` requests IPv4 host interfaces. `127.0.0.1` limits the published port to IPv4 loopback on the host.

For demos that only need local testing, loopback binding is usually the safer choice. For a service that must be reachable remotely, you still need an appropriate firewall, permitted network exposure, authentication and HTTPS where applicable. Simply binding a port does not create an application security model.

Within managed cloud environments, there may be several independent control points: host firewall, VPC/network ACL, cloud security group, subnet routing, load balancer listener, Kubernetes NetworkPolicy and provider firewall. A Podman port flag cannot override network controls outside its scope.

---

## 19. Why rootless Podman matters for port publishing

Rootless Podman runs containers under an unprivileged user account rather than requiring a root daemon for every task. This reduces the blast radius of many common operations, but it also means network setup may use special rootless networking components and user namespace mechanisms.

Privileged host ports (traditionally below 1024) have extra restrictions on typical Linux systems. This lab intentionally uses 8080 and 9090, which are high ports and fit rootless experimentation. Do not “fix” a publishing error by immediately adding `--privileged`: that disables important isolation protections and does not solve an ordinary host-port collision.

If a port looks bound in Podman but the OS inspection output differs from an old tutorial, first verify your Podman version, rootless versus rootful mode, and networking backend. Treat implementation details as version-sensitive while keeping the end-to-end connectivity test as the deciding factor.

---

## 20. Detecting HTTP versus TCP failures

A few examples illustrate how signal interpretation matters:

- **Connection refused:** TCP connect failed promptly because nothing accepted the connection at that address/port or the forwarder rejected it. Often wrong host port, stopped container or wrong listening address.
- **Connection timed out:** Traffic may be dropped by filtering, a routing problem or unreachable network path. It is not enough evidence to blame Flask.
- **HTTP 404:** Network connection worked and a server responded, but the requested route was not found.
- **HTTP 500:** The server answered and encountered an application error; inspect application logs rather than immediately changing port publishing.
- **HTTP 200 with wrong body:** Connectivity works but the endpoint may point to the wrong application instance or an unexpected application version.
- **TLS handshake error:** If you request HTTPS from a plain HTTP Flask endpoint, transport may be present but protocol expectations differ.

Always write down the precise URL, host, path, scheme (`http` versus `https`) and timestamp when recording failures.

---

## 21. Failure-domain method: troubleshoot from inside out

When an application appears inaccessible, test in this order:

**A — File/image:** Was the expected code built? `podman images` and `podman image inspect`.

**B — Container lifecycle:** Is the intended instance running? `podman ps -a`.

**C — Application process:** Does the server start or throw exceptions? `podman logs <container>`.

**D — Container listener:** Does the app bind its actual internal port and correct interface? In this case, inspect Flask's configuration and logs.

**E — Runtime publication:** Does `podman port <container>` report the mapping you think exists?

**F — Host request:** Can a client on the Podman host reach the published port with `curl`?

**G — External request:** If external reachability is required, does the remote client target the correct host IP, and do firewalls/routes allow it?

This prevents noisy troubleshooting: if step F works but step G fails, rebuilding Python dependencies is unlikely to solve the issue.

---

## 22. Interview question: Can two containers use container port 8080?

Yes—assuming each has an isolated network namespace or otherwise non-conflicting network setup. Internal port numbers can be reused across separate containers because their listeners are in different network contexts. What cannot usually be duplicated is the same **published host IP + host port + protocol** binding. For example, one container may publish `8080:8080` and another `9090:8080` simultaneously.

The exception is when containers share a network namespace, such as containers in the same pod: they share the same listening address and port space within that namespace. This becomes important when you advance to Kubernetes and Podman pods.

---

## 23. Interview question: Does changing `EXPOSE` change the app port?

No. `EXPOSE 9090` would advertise port 9090 in image metadata, but our application would still listen on 8080 unless the Python code or its runtime configuration changed. If you wrote `EXPOSE 9090` and ran `-p 9090:9090`, forwarding would deliver traffic to a port where the app likely is not listening. A realistic debugging interview might deliberately introduce this mismatch and ask you to find it.

A useful technique is to maintain a simple four-column table: “App listen address, app listen port, published host address, published host port.” Many networking incidents come down to one cell being wrong.

---

## 24. Interview question: Why does `curl 8080` fail after remapping?

Because the host-side listener on 8080 was retired when the first container was stopped, and the second container was started with host publication on 9090. The route now expects `curl http://127.0.0.1:9090`. The *internal* service port remains 8080. This distinction is visible in your genuine second screenshot and is one of the most valuable outcomes of this exercise.

Do not describe the failed 8080 request as an application outage without checking what was intended to be listening there.

---

## 25. Safe cleanup and idempotent practice

The original worksheet's `podman stop -a && podman rm -a` may stop and delete unrelated containers from earlier labs. Engineers should prefer scoped cleanup in shared or persistent environments:

```bash
podman rm -f webapp webapp2 webapp-conflict webapp-alt webapp-auto 2>/dev/null || true
```

Removing a container deletes its writable layer; the built image remains unless explicitly removed. For a stateless Flask greeting demo that is fine. For stateful database workloads it could cause real data loss if storage were not properly persisted. This connects to the earlier labs on volumes and recovery.

An idempotent test setup includes an explicit name policy, cleanup commands and no assumption that host ports are always free. Avoid commands that sweep away the entire environment without asking what other projects are running.

---

## 26. Where the lab fits in real Cloud/DevOps workflows

**CI pipelines:** Build an image, launch a temporary container on an available port, wait for readiness, issue a smoke request, and fail the build if the expected HTTP response is absent.

**Local development:** Run multiple versions of a service internally on the same port but publish them to distinct host ports for comparison.

**Microservice debugging:** Determine whether a failure is in service startup, in-container binding, Podman networking, DNS or externally published endpoints.

**Blue/green experiments:** Deploy a new version on another host port, validate it and then shift the routing layer. A temporary port swap is not a complete production rollout method, but it demonstrates the core idea of verifying the destination before cutting traffic over.

**Service security:** Publish only ports and network interfaces that callers genuinely need. Container networking forms only one layer of the security boundary.

---

## 27. How this translates to Kubernetes and OpenShift

In a Kubernetes Pod spec, `containerPort` is primarily a declaration of the port used by the container. It does not, by itself, make the workload externally reachable. A Kubernetes **Service** selects and provides stable network access to Pods, usually through service ports mapped to target ports. External ingress often adds an Ingress controller, Gateway API resource or LoadBalancer Service, depending on the cluster.

The conceptual progression looks like:

```text
Podman: app listens -> EXPOSE metadata -> -p publishes to host
K8s:    app listens -> containerPort describes -> Service/Ingress routes traffic
```

These are **analogies**, not one-to-one replacement flags. Kubernetes adds scheduling, service discovery, endpoint membership, readiness behavior, network policies and many other cluster-level considerations.

An OpenShift engineer should never assume that exposing a Containerfile port automatically creates a Kubernetes Service or external Route.

---

## 28. A repeatable mini-checklist for future incidents

Before saying “Networking is broken,” capture:

1. **Where is the client?** VM host, laptop, container, pod or another machine?
2. **Exactly what URL failed?** Include scheme, host/IP and port.
3. **Which container is running?** Name, image, creation time and state.
4. **What port does the application listen on?** Inspect configuration and logs.
5. **Which host port is published?** `podman port`.
6. **What changed since the last successful request?** New mapping, container recreation, app build, firewall rule?
7. **What does `curl -v` say?** Refused, timed out, HTTP error or successful response?
8. **Can you reproduce the problem and document the fix?** Use scoped commands and evidence.

An investigator who can answer these questions will usually troubleshoot faster than someone who memorizes ten random flags.

---

## 29. Practical exercises that build confidence

These are **optional future exercises**, not claims of completed work:

**Exercise A — Make `EXPOSE` intentionally wrong.** Change it to `EXPOSE 9090`, keep Flask listening on 8080, and compare `-P` against an explicit correct `-p HOST:8080` mapping. Explain why metadata and runtime truth differ.

**Exercise B — Break the listening address.** Change Flask's `0.0.0.0` to `127.0.0.1` inside the container. Rebuild and test publishing. Observe any backend-specific behavior and compare logs.

**Exercise C — Deliberate collision.** Keep a container on host port 9090 and attempt to publish another on the same host port. Capture the exact error with timestamps and resolve by choosing 9091 or freeing the port.

**Exercise D — Bind local-only.** Run `-p 127.0.0.1:9092:8080`, verify from the host and examine the host listener. Do not publish testing apps to the public Internet solely for the exercise.

**Exercise E — Use `-P`.** Examine the randomized host port via `podman port` and write a script that discovers it before calling curl.

**Exercise F — Health endpoint.** Add `/healthz` and return a simple JSON health record; explain why successful startup alone is not always readiness.

**Exercise G — Compare networking scopes.** If allowed by lab environment, inspect rootless vs rootful network behavior without using `--privileged` as a shortcut.

---

## 30. Twenty interview questions, with practical answers

**Q1. What does `EXPOSE 8080` do?**  
It documents that the image expects an application on port 8080, usually TCP. It does not publish a host port or guarantee a listener exists.

**Q2. What does `-p 9090:8080` mean?**  
Host port 9090 forwards to container port 8080. The host port can differ from the app port.

**Q3. What does `-P` mean?**  
Publish all exposed ports on dynamically chosen host ports. Use `podman port` to discover the actual mapping.

**Q4. Why did the Flask app bind `0.0.0.0`?**  
To listen on the container's IPv4 interfaces, not only the container loopback address.

**Q5. Is `EXPOSE` required for `-p` to work?**  
No. Explicit publishing can work independently of the metadata, provided a service listens on the specified container port.

**Q6. How do you check a running container's published ports?**  
`podman port NAME` or the `PORTS` column in `podman ps`.

**Q7. How do you verify a published HTTP endpoint?**  
`curl -v http://HOST:HOSTPORT/` and examine status and response body.

**Q8. Why can `podman ps` say Up while HTTP fails?**  
The container process may be up but listening on the wrong port, unhealthy, serving a different route or failing inside application code.

**Q9. Why can two containers listen on internal port 8080?**  
Separate network namespaces mean their internal listeners do not necessarily conflict.

**Q10. Why can they conflict when publishing host port 9090?**  
Only one listener/forwarding configuration can normally own the same host IP, TCP/UDP protocol and port at one time.

**Q11. Why did `localhost:8080` fail when `localhost:9090` succeeded?**  
The old host mapping had been stopped; the active container published host port 9090 while still listening on container port 8080.

**Q12. Does `curl` from inside the container test host publishing?**  
No. It primarily tests the container-local path. You must call the published host address from an appropriate host-side client.

**Q13. Does `0.0.0.0` equal public internet access?**  
No. It is a binding scope, and actual access still depends on routing, firewall, platform restrictions and the client location.

**Q14. How can you make a port available only to local development tools?**  
Explicitly bind a loopback host address such as `-p 127.0.0.1:9090:8080`.

**Q15. When is `ss` useful?**  
To inspect local listening sockets and protocol state from the host's perspective.

**Q16. When is `lsof` useful?**  
To investigate which visible process owns a host listener; process visibility depends on permissions and network implementation.

**Q17. Why must we distinguish HTTP failures from TCP failures?**  
A TCP refusal points toward socket/forwarding issues; HTTP 404 or 500 proves some server answered and indicates higher-level problems.

**Q18. Why not fix networking by using `--privileged`?**  
It disables security isolation and is unnecessary for ordinary host port mapping. Diagnose the actual cause.

**Q19. Is Flask's built-in server production ready?**  
No. It is suitable for this controlled teaching exercise, not a hardened production deployment.

**Q20. What is the key engineering takeaway from this lab?**  
Treat image port metadata, application listening, host forwarding and client connectivity as separate claims. Confirm each with the appropriate test and preserve evidence.

---

## 31. Rapid-reference commands

```bash
# From the repository root:
podman build -t exposed-app .

# Known host-port mapping:
podman run -d --name webapp2 -p 9090:8080 exposed-app
podman ps
podman port webapp2
curl -v http://127.0.0.1:9090/
sh tests/smoke-test.sh 9090

# Inspect application errors:
podman logs webapp2

# Optional host socket investigation:
ss -tulnp | grep ':9090' || true

# Controlled port conflict: attempt while webapp2 holds 9090:
podman run -d --name webapp-conflict -p 9090:8080 exposed-app

# Safe cleanup of only this lab's names:
podman rm -f webapp webapp2 webapp-conflict webapp-alt webapp-auto 2>/dev/null || true
```

The commands are a reproducible runbook, not a transcript claiming every line was executed in the captured session. The [README](README.md) names the two screenshots and records precisely which results are visible.

---

## 32. Glossary — keep for long-term revision

**Bind:** Attach a listening socket to an IP address and port.  
**Container port:** Transport port within the container networking environment.  
**Host port:** Transport port made available on the Podman host.  
**Port publishing:** Runtime configuration forwarding host traffic to a container service.  
**`EXPOSE`:** Image metadata documenting an expected container port.  
**Loopback:** Network interface whose addresses refer back to the current network namespace, often `127.0.0.1`.  
**Network namespace:** Linux isolation mechanism providing an independent network view.  
**HTTP:** Application protocol that defines requests and responses.  
**TCP:** Transport protocol that delivers ordered byte streams between endpoints.  
**Connection refused:** Connection attempt failed at the TCP/socket level.  
**Smoke test:** Small test confirming the most essential behavior of a deployed component.  
**Rootless:** Running Podman as an ordinary user with user-namespace/networking mechanisms where supported.  
**WSGI:** Python interface commonly used by application servers to host web apps.  
**NAT:** Network Address Translation; one possible mechanism used in network forwarding.  
**Port conflict:** Two processes/configurations attempting to use the same host address, protocol and listening port.

---

## 33. Final professional interpretation

This lab has a clean, evidence-backed success case: a Flask service built into a Podman image, a container launched with a published port, and an HTTP response observed when the **host port changed from 8080 to 9090**. The real troubleshooting lesson is understanding why the retired endpoint did not respond while the new one did.

Do not inflate this into a claim of application-scale reliability, remote reachability or exhaustive security testing. The missing port-conflict capture should be treated as an honest follow-up exercise. Reliable engineering is not merely getting a green command once; it is knowing what that command proved, which hypotheses remain untested and how the next test will remove uncertainty.

### Official references

- [Podman run: publish and publish-all](https://docs.podman.io/en/stable/markdown/podman-run.1.html)
- [Podman build: Containerfile and build context](https://docs.podman.io/en/latest/markdown/podman-build.1.html)
- [Docker documentation: exposing versus publishing ports](https://docs.docker.com/engine/containers/run/)

Return to the **[main Lab 08 README](README.md)** for the exact exercise steps and genuine screenshots.
