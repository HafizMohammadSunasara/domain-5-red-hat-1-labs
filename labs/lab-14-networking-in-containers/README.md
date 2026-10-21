# Lab 14 — Networking in Containers

> **Domain 5 → Linux and Open Source → Red Hat 1**  
> **Focus:** Podman networks, network inspection, bridge networking, port publishing, and Nginx connectivity  
> **Status:** **Completed — self-reported.** The learner reported completing the lab and understanding its concepts; this repository does **not** contain independently authenticated execution logs or screenshots.  
> **Companion:** [DEEP-DIVE.md](DEEP-DIVE.md) — underlying networking, security, rootless Podman, diagnostic reasoning, and interview preparation.

## Overview

This exercise progresses from **discovering existing Podman networks**, to **creating a custom network**, to **publishing an Nginx port and verifying its network membership**. It is an instructional lab, not a claim of production deployment, load testing, or independent certification.

### Learning objectives

- Explain the role of networks in container-to-container and host-to-container communication.
- List and inspect default and custom Podman networks.
- Create a named network using Podman's network management interface.
- Run an Nginx container and publish container port `80` on host port `8080`.
- Diagnose basic connectivity, runtime and port-binding problems.
- Attach a newly created container to a custom network and inspect its settings.

### Prerequisites

- Linux (RHEL, CentOS Stream, or Fedora recommended); Podman installed.
- Shell access, permissions to run containers, and internet connectivity to fetch the Nginx image.
- A free host port `8080` and free container name `webapp`, or willingness to resolve conflicts safely.
- `curl` for the host-side HTTP test.

**Installation commands included in the course prerequisites** (use **only** the command appropriate for your operating system; don't run both):

```bash
sudo dnf install podman             # RHEL/Fedora-based systems
sudo apt-get install -y podman     # Debian/Ubuntu systems
```

Optional baseline checks:

```bash
podman --version
podman info
```

**Safety before starting:** Check `podman ps -a` and `ss -ltn` if you have existing lab containers. This lab uses the generic name `webapp` and host port `8080`, which might already be in use. Do not remove someone else's container merely to make the examples run.

---

## Task 1 — List Podman Networks

### Subtask 1.1 — Check available networks

**Original instructor command:**

```bash
podman network ls
```

**Illustrative output** (IDs, columns, available networks, and drivers are version/environment-specific):

```text
NETWORK ID    NAME       DRIVER
2f259bab93aa  podman     bridge
```

**What to observe:**

- `NAME` — network identifier, often `podman` for the managed default bridge network.
- `DRIVER` — implementation/type, e.g. `bridge`.
- `NETWORK ID` — network identifier if shown by this version.

**Important nuance:** A rootless container's *default* connectivity may use `pasta` or `slirp4netns` instead of joining the `podman` bridge. Do not assume every Podman installation has exactly the output above or that every container belongs to this bridge.

### Subtask 1.2 — Verify default-network details

**Original instructor command:**

```bash
podman network inspect podman
```

Inspect the JSON for the network's name, driver, subnets, gateway, IP address management (IPAM) and DNS-related fields. Keys/values differ by Podman version and network backend; e.g. a `subnets` array can contain `subnet` and `gateway` values.

**Expected result:** A JSON description if a network named `podman` is present. If not, inspect the name actually shown by `podman network ls` rather than inventing a default network.

**Checkpoint 1:** You can identify at least one network and explain what its network and IP configuration represent.

---

## Task 2 — Inspect Network Settings

### Subtask 2.1 — Create a custom network

**Original instructor command:**

```bash
podman network create lab-network
```

**Original verification command:**

```bash
podman network ls | grep lab-network
```

**Expected observation:** `lab-network` appears in the network listing. `grep` returning nothing is a useful signal to re-check creation output or name, not proof of a specific root cause.

**Explanation:** The network's existence is independent of an individual container. Creating the network does **not** automatically attach already running containers to it.

### Subtask 2.2 — Inspect the custom network

**Original instructor command:**

```bash
podman network inspect lab-network
```

**Expected observation:** Network configuration in JSON format. Look for (when supported by your backend):

| Field / concept | What to examine |
| --- | --- |
| `name` | Network identifier: `lab-network` |
| `driver` | Usually `bridge` for a local custom bridge network |
| `subnets` / `subnet` | Address range allocated to connected containers |
| `gateway` | Gateway for that network when configured |
| `ipam_options` / IPAM | Address allocation configuration, where available |
| `dns_enabled` | Whether network-scoped DNS functionality is enabled |

**Original troubleshooting check:**

```bash
podman info
```

Use this to examine Podman runtime/environment information when creation fails; it does not by itself prove that the failure is a rootless-permissions issue. Check the **actual error** and the available network backend.

**Checkpoint 2:** `lab-network` exists and its details can be inspected.

---

## Task 3 — Run Containers with Port Publishing

### Subtask 3.1 — Run Nginx with a published port

**Original instructor command:**

```bash
podman run -d --name webapp -p 8080:80 docker.io/library/nginx
```

**Breakdown:**

| Part | Meaning |
| --- | --- |
| `podman run` | Create and start a container from the image |
| `-d` | Run detached; does **not** guarantee the process remains healthy |
| `--name webapp` | Assign a readable container name |
| `-p 8080:80` | Publish **host** TCP port 8080 to **container** TCP port 80 |
| `docker.io/library/nginx` | Pull/use the official Nginx image (implicit default tag if not specified) |

**Note:** `-p 8080:80` may bind on available host interfaces, rather than localhost only. A more tightly scoped **optional** local-lab alternative is `-p 127.0.0.1:8080:80`. The original command is retained above for course fidelity. Avoid publicly exposing lab services unintentionally.

### Subtask 3.2 — Verify host-side HTTP accessibility

**Original instructor command:**

```bash
curl http://localhost:8080
```

**Expected observation:** HTML containing the Nginx welcome page if the container is running and its port is reachable. Output may differ with image content, HTTP configuration, or image version.

**Original troubleshooting commands:**

```bash
podman ps
sudo firewall-cmd --list-ports
```

- `podman ps` checks **running** containers; use `podman ps -a` if it exited.
- `sudo firewall-cmd --list-ports` lists explicitly opened firewalld ports, **not** a definitive localhost connectivity test. A local `curl localhost` failure is not automatically a firewall rule problem.
- If the HTTP check is empty or refused, inspect the container's status, logs, and effective published ports:

```bash
podman ps -a --filter name=webapp
podman logs webapp
podman port webapp
```

**Host/VM boundary:** Run `curl http://localhost:8080` in the same Linux environment where Podman published the port. If Podman runs inside a RHEL VM, `localhost` in the Windows host browser means **Windows**, not automatically that VM; VirtualBox networking/port forwarding may need separate configuration.

### Subtask 3.3 — Attach the container to `lab-network`

**Original instructor commands:**

```bash
podman stop webapp
podman run -d --name webapp -p 8080:80 --network lab-network docker.io/library/nginx
```

**Important course correction:** `podman stop webapp` **stops** the container, but it does **not** remove the container object or release the existing name. The second command can fail with `the container name "webapp" is already in use`.

**Corrected, reproducible sequence for this disposable Nginx lab** (only if this `webapp` is the container you intentionally created here):

```bash
podman stop webapp
podman rm webapp
podman run -d --name webapp -p 8080:80 --network lab-network docker.io/library/nginx
```

- `podman rm webapp` releases the stopped container's name.
- `--network lab-network` selects the new custom network **at creation time**.
- Removing the container discards that container's non-persistent writable-layer changes. Only do this for the replaceable lab container, not a container holding important data.

**Original instructor inspection command:**

```bash
podman inspect webapp | grep -A 5 "Networks"
```

This text search can truncate information or miss backend-specific formatting. Use these **optional stronger checks** alongside it:

```bash
podman inspect webapp --format '{{json .NetworkSettings.Networks}}'
podman network inspect lab-network
podman port webapp
curl http://localhost:8080
```

**Expected observations:** The inspected container refers to `lab-network` when the network backend exposes that mapping; port publishing remains configured; and the Nginx HTTP endpoint is reachable.

**Alternate concept, not required by the instructor:** If you want to attach an *existing* running container without deleting and recreating it, Podman supports:

```bash
podman network connect lab-network webapp
```

This adds a network attachment; it is **not** equivalent to removing existing network attachments or making the network the container's sole network. Check actual support and inspect the result in your environment.

**Checkpoint 3:** Nginx responds on host port 8080 after creation on the custom network, and inspection shows the intended network attachment.

---

## Troubleshooting runbook

| Symptom | Likely checks | Safe next action |
| --- | --- | --- |
| `webapp` name already in use | `podman ps -a --filter name=webapp` | Reuse the intended container, rename yours, or remove **only** your disposable stopped lab container |
| Host port 8080 already occupied | `ss -ltnp`, `podman ps -a`, `podman port webapp` | Free the specific known owner of the port or choose a different host port |
| HTTP connection refused | `podman ps -a`, `podman logs webapp`, `podman port webapp` | Confirm service running and port binding before changing firewall rules |
| Network not found | `podman network ls` | Create it or correct the network name |
| Network creation fails | Error output, `podman info` | Check backend, privileges, pre-existing subnet and rootless setup; don't guess |
| `podman inspect | grep -A 5` shows little | JSON layout differs | Use structured `--format` inspection and network inspect |
| Works in RHEL VM but not Windows browser | Distinct localhost environments | Check VM IP, adapter mode, host/guest forwarding and firewall exposure |
| Expected bridge unavailable | Rootless backend/version differences | Inspect actual network list and selected runtime network mode |

### Useful reproducible diagnostic sequence

```bash
podman ps -a
podman network ls
podman network inspect lab-network
podman inspect webapp --format '{{json .NetworkSettings.Networks}}'
podman port webapp
podman logs webapp
curl -I http://localhost:8080
```

Treat command output as **live evidence from your own machine**; sample outputs in this document are illustrative, not archived execution logs.

---

## Suggested evidence (optional; attach only genuine captures)

1. **Network configuration:** `podman network ls` together with `podman network inspect lab-network` showing a custom network.
2. **Working connection:** `curl http://localhost:8080` plus a clear network assignment for `webapp` after Task 3.3.

If you have no screenshots or log captures, leave evidence status as self-reported rather than inserting recreated terminal images.

## Safe cleanup (optional; not an instructor task)

Check what will be removed first:

```bash
podman ps -a --filter name=webapp
podman network ls
```

If these are **your disposable Lab 14 resources**, you may remove them:

```bash
podman stop webapp
podman rm webapp
podman network rm lab-network
```

This is intentionally **targeted cleanup**; do not delete all Podman containers/networks on the host. The original handout does not require a cleanup step. If you want to revisit this lab, you may keep the network for later experiments.

## Lab completion checklist

- [x] Task 1.1 — listed networks with `podman network ls` (**learner-reported**)
- [x] Task 1.2 — inspected `podman` network (**learner-reported**)
- [x] Task 2.1 — created and located `lab-network` (**learner-reported**)
- [x] Task 2.2 — inspected subnet/gateway/IPAM details (**learner-reported**)
- [x] Task 3.1 — started Nginx with host port 8080 (**learner-reported**)
- [x] Task 3.2 — tested HTTP accessibility (**learner-reported**)
- [x] Task 3.3 — attached/recreated on custom network and inspected settings (**learner-reported**)

**Verification level:** Self-reported completion. No original command results, running environment, benchmark, or screenshot was independently verified while preparing this documentation.

## Key takeaways

1. **Network listing** and **network inspection** answer different questions: what exists vs how it is configured.
2. A **custom bridge network** can group/isolate connected application services, subject to host/rootless network backend behavior and security policy.
3. **Port publishing** connects a host interface/port to a container listening port; it is not the same as assigning a container an IP address.
4. **Stop is not remove**: a stopped container continues to reserve its name, so recreate workflows must consider lifecycle explicitly.
5. To debug connectivity, examine container health, listening ports, network attachment, routing and the correct host/VM context rather than guessing.

## Next steps

- Practice `podman network connect lab-network webapp` and then inspect both networks.
- Create a second container on `lab-network`; investigate container-to-container communication and network-scoped DNS.
- Compare `-p 8080:80` with `-p 127.0.0.1:8080:80` and understand exposure.
- Study network namespaces, forwarding, NAT, rootless networking, and how these map to Kubernetes/OpenShift services.

---

**Maintainer:** Hafiz Mohammad Sunasara · [Back to all labs](../LABS-INDEX.md) · [Engineering Proof of Work](../../evidence/PROOF-OF-WORK.md) · [Deep Dive](DEEP-DIVE.md)
