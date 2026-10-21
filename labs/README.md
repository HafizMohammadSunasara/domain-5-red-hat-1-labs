# Lab 18 — Kubernetes Pod Deployment

> **Track:** Domain 5 → Linux and Open Source → Red Hat 1  
> **Status:** **Completed — self-reported by learner** (all lab tasks, including the optional access test, reported as completed).  
> **Focus:** Kubernetes Pod manifests · `kubectl apply` · status · inspection · logs · port-forwarding  
> **Companion:** [DEEP-DIVE.md](DEEP-DIVE.md) for internal architecture, networking, failure diagnosis, production considerations, and interview preparation.

## What this lab proves — and what it does not

This lab teaches how to declare an Nginx **Pod** in YAML, submit it to a Kubernetes/OpenShift cluster, check its running state, examine logs/events, and optionally access the web server through local port forwarding.

**Evidence integrity:** The learner reported successfully completing the practical. This repository provides a reproducible manifest, the lab's commands, expected results, and troubleshooting guidance; it does **not** include original terminal logs, cluster screenshots, a live cluster connection, or independently verified execution results. Example output below is labeled **expected**, not historical evidence.

## Objectives (all instructor objectives)

- Understand `apiVersion`, `kind`, `metadata`, `spec` and `containers` in a Pod YAML manifest.
- Deploy a basic Pod to Kubernetes or OpenShift.
- Check Pod readiness/status; inspect events, configuration and logs for troubleshooting.
- **Optional:** Use `kubectl port-forward` to view Nginx on port 8080.

## Prerequisites and environment setup

**Instructor prerequisites:** A working Kubernetes/OpenShift cluster (Minikube, Kind, OpenShift Local, or equivalent), `kubectl` or `oc` installed/configured, a text editor (vim/nano/VS Code), and basic YAML familiarity.

**K3s option on a dedicated RHEL lab VM:** K3s bundles Kubernetes components and a `kubectl` client. On a K3s installation where normal-user kubeconfig access has not been set up, use `sudo k3s kubectl` **instead of** `kubectl` for the commands below. The instructor's original `kubectl` commands are retained verbatim in this guide. This lab does **not** require a separate Dockerfile, Compose file, or Podman image build.

### Preflight — verify the cluster (recommended checks)

```bash
kubectl version --client
kubectl config current-context
kubectl cluster-info
kubectl get nodes
```

If using K3s on RHEL instead:

```bash
sudo k3s kubectl get nodes
```

- Nodes should be accessible; for a simple single-node lab, look for `Ready`.
- Check the active namespace/context before applying any resource.
- On OpenShift, `oc` can perform equivalent Pod operations; check the target project with `oc project`.
- Do not assume merely installing `kubectl` creates a Kubernetes cluster.

## Task 1 — Write a Pod YAML Manifest

### Subtask 1.1 — Create `simple-pod.yaml`

1. Open a text editor (`nano`, `vim`, or VS Code).
2. Create the file named `simple-pod.yaml` (included directly beside this README).
3. **Instructor's exact YAML:**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod
  labels:
    app: nginx
spec:
  containers:
  - name: nginx-container
    image: nginx:latest
    ports:
    - containerPort: 80
```

To create it on a local Linux machine, for example:

```bash
mkdir -p ~/kubernetes-lab-18
cd ~/kubernetes-lab-18
nano simple-pod.yaml
```

**Expected outcome:** A syntactically valid Pod manifest describing one Nginx container.

| Key | Meaning |
| --- | --- |
| `apiVersion: v1` | Core Kubernetes API version for Pods |
| `kind: Pod` | Resource type the API should create/update |
| `metadata.name: nginx-pod` | Name of this Pod in its namespace |
| `metadata.labels.app: nginx` | Searchable/selector-friendly metadata |
| `spec` | Desired workload configuration |
| `spec.containers` | List of containers sharing this Pod |
| `name: nginx-container` | Container identifier inside the Pod |
| `image: nginx:latest` | Container image requested by the instructor |
| `containerPort: 80` | Declared container listening port, **not** a host-port mapping |

**Key learning:** YAML indentation matters. `containerPort: 80` does not itself create a Kubernetes `Service` or expose port 80 to external users. For reproducible deployments in serious environments, pin an image version/digest instead of the mutable `latest` tag; keep `latest` here to preserve the exercise.

**Extra validation (not an instructor step):**

```bash
kubectl apply --dry-run=client -f simple-pod.yaml
```

Client dry-run checks whether the client can prepare the resource; it does not prove the Pod will actually start or that networking is functional.

## Task 2 — Deploy the Pod

### Subtask 2.1 — Apply the YAML file

**Instructor command:**

```bash
kubectl apply -f simple-pod.yaml
```

**Expected example:**

```text
pod/nginx-pod created
```

A later repeat may say `configured` or `unchanged` — these are not necessarily errors. Kubernetes receives the manifest through the API server, schedules the Pod onto a suitable node, and the kubelet starts the container using the node's container runtime.

### Subtask 2.2 — Verify Pod deployment

**Instructor command:**

```bash
kubectl get pods
```

**Expected example (values vary):**

```text
NAME        READY   STATUS    RESTARTS   AGE
nginx-pod   1/1     Running   0          10s
```

- `READY 1/1`: One declared container is currently reported ready.
- `STATUS Running`: Pod is assigned to a node and at least one container is running or starting/restarting; examine readiness and state separately for certainty.
- `RESTARTS`: Number of container restarts observed.
- `AGE`: Time since Pod creation.

**Instructor troubleshooting commands (do not skip):**

For a Pod stuck in `Pending`:

```bash
kubectl describe pod nginx-pod
```

For `CrashLoopBackOff`/container crashes:

```bash
kubectl logs nginx-pod
```

**Additional useful checks:**

```bash
kubectl get pods -o wide
kubectl get events --sort-by=.metadata.creationTimestamp
kubectl logs nginx-pod --previous
```

`--previous` applies if a previous container instance exists. Other common statuses include `ErrImagePull` and `ImagePullBackOff` when the image cannot be retrieved. Check events in `describe` before changing anything.

## Task 3 — Inspect Pod Status and Logs

### Subtask 3.1 — Check Pod details

**Instructor command:**

```bash
kubectl describe pod nginx-pod
```

**Fields to inspect:**

- **Namespace and name** — which Pod you are examining.
- **Node** — the host scheduled to run the Pod.
- **Status and Conditions** — scheduling, initialization, readiness.
- **IP** — Pod's cluster address (when assigned).
- **Containers** — image, container ID, state, restarts, ports.
- **Events** — scheduling, pull, start, probe or configuration failures.

**Expected outcome:** Details are displayed for `nginx-pod`; exact fields/values depend on the live cluster.

### Subtask 3.2 — View Pod logs

**Instructor command:**

```bash
kubectl logs nginx-pod
```

**Expected outcome:** Standard-output/error logs from the Nginx container, which may include startup notices and access entries. Logs can be quiet before traffic is sent. `kubectl logs` is not a full historical audit-log system and does not by itself show every file-based log from the container.

**Useful optional follow-ups:**

```bash
kubectl logs -f nginx-pod
kubectl logs nginx-pod -c nginx-container
```

Stop a streaming log with `Ctrl+C`.

### Subtask 3.3 — Access the Pod (optional instructor task)

**Instructor command, in Terminal A:**

```bash
kubectl port-forward nginx-pod 8080:80
```

Expected concept: A temporary local tunnel connects **your command-running machine's `localhost:8080`** to port `80` on the Pod. Leave this command running while testing.

**Instructor URL:**

```text
http://localhost:8080
```

**Open the URL in a browser on the same machine**, or test from **Terminal B**:

```bash
curl http://localhost:8080
```

**Expected outcome:** The Nginx welcome HTML page. If Nginx is running in a RHEL VirtualBox VM and your browser is on the Windows host, `localhost` on Windows is **not** the RHEL VM's loopback. Test with `curl` inside the VM first; do not publicly expose the port just to make debugging convenient.

To stop the tunnel, press `Ctrl+C` in Terminal A. If host port 8080 is occupied, a separate local port (e.g., `8081:80`) is a diagnostic alternative, not the instructor's original command.

## End-of-lab verification checklist

- [x] Task 1.1 — Manifest created and understood (learner-reported).
- [x] Task 2.1 — Manifest applied to the cluster (learner-reported).
- [x] Task 2.2 — Pod status verified (learner-reported).
- [x] Task 3.1 — Pod described/inspected (learner-reported).
- [x] Task 3.2 — Container logs inspected (learner-reported).
- [x] Task 3.3 — Optional local port forwarding practiced (learner-reported).

These checked items record **the learner's statement**, not an independent machine-verified transcript.

## Common problems and first checks

| Symptom | What to investigate | First command |
| --- | --- | --- |
| `kubectl: command not found` | CLI not installed or PATH incorrect; K3s may bundle its own | `kubectl version --client` / `sudo k3s kubectl get nodes` |
| Connection refused to API server | Wrong current context, kubeconfig, cluster down | `kubectl cluster-info` |
| Pod `Pending` | No eligible node, CPU/memory, taints, image/storage setup | `kubectl describe pod nginx-pod` |
| `ErrImagePull` / `ImagePullBackOff` | Registry resolution, authentication or network | `kubectl describe pod nginx-pod` |
| `CrashLoopBackOff` | Process repeatedly exiting; inspect reason and prior logs | `kubectl logs nginx-pod --previous` |
| Logs empty | Application has not emitted much stdout/stderr, or no traffic | `kubectl logs nginx-pod` |
| Browser cannot access port 8080 | Port forward not running; browser and kubectl in different machines; port occupied | `kubectl port-forward nginx-pod 8080:80` |
| OpenShift security error | Image/security context may conflict with project policy | `oc describe pod nginx-pod` |

## Optional safe cleanup

This is an **additional** cleanup step, not supplied as an instructor task:

```bash
kubectl delete -f simple-pod.yaml
```

This removes the Pod declared by this manifest; **it does not uninstall Kubernetes or delete other workloads**. A bare Pod is not automatically recreated by a Deployment after it is deleted.

## Evidence suggestions (optional; never fabricate)

If you retained genuine outputs/screenshots from your session, helpful evidence would be:

1. `kubectl get pods` showing `nginx-pod` ready/running, with the cluster context visible.
2. `kubectl describe pod nginx-pod` or port-forward + `curl` demonstrating inspection or reachability.

Do not label sample outputs as actual execution logs. Avoid publishing kubeconfig tokens, credentials, internal IPs or sensitive cluster details unnecessarily.

## Conclusion — Instructor learning outcomes

The learner reports having:

1. Created a Pod YAML manifest.
2. Deployed the Pod using `kubectl apply`.
3. Verified Pod status and inspected logs for troubleshooting.
4. Practiced optional port forwarding to reach Nginx.

This lab introduces **a bare Pod**, not a production-ready application platform. Production workloads generally use a Deployment (or another appropriate controller), a Service, health probes, policies and pinned images.

## Next steps (instructor + deeper practice)

- Explore **multi-container Pods** and when sidecars make sense.
- Study **Pod lifecycle**, restart policies and **readiness/liveness/startup probes**.
- Compare a bare **Pod** to a **Deployment + Service**.
- Continue with [Deep Dive](DEEP-DIVE.md) for the internal API → scheduler → kubelet workflow.

## References

- [Kubernetes — Pods](https://kubernetes.io/docs/concepts/workloads/pods/)
- [Kubernetes — kubectl commands](https://kubernetes.io/docs/reference/kubectl/)
- [OpenShift documentation](https://docs.openshift.com/)

**Maintained by:** Hafiz Mohammad Sunasara · **Track:** Domain 5 / Linux and Open Source / Red Hat 1.
