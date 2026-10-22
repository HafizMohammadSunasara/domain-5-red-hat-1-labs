# Lab 18 — Engineering Deep Dive: Kubernetes Pod Deployment

**Track:** Domain 5 → Linux and Open Source → Red Hat 1  
**Lab status:** Completed — **learner self-reported**, not independently verified.  
**Start with:** [Practical Runbook](README.md) · [Actual Pod Manifest](simple-pod.yaml)

> This document builds an engineering mental model around the instructor's Lab 18: a single Nginx Pod, the Kubernetes control plane, YAML fields, status/conditions, logs/events, and local port forwarding. Sample commands and output descriptions are **educational references**, not copied execution evidence.

## 1. The engineering problem

With Podman or Docker, you typically specify **how to run a container on one machine**:

```bash
podman run -d --name nginx -p 8080:80 docker.io/library/nginx:alpine
```

With Kubernetes you declare **what state you want** and ask the cluster to arrange it:

```bash
kubectl apply -f simple-pod.yaml
```

Kubernetes stores the requested object, decides which node should host the Pod, invokes a container runtime through a kubelet, and exposes the object's current state through its API. **This is not the same as promising a bare Pod will always exist:** the Pod's containers can be restarted on their assigned node, but deleting a standalone Pod does not make a Deployment controller recreate it.

### The simplest useful picture

```text
Developer / engineer
        |
        | kubectl apply -f simple-pod.yaml
        v
 Kubernetes API Server ---> desired Pod object stored in etcd
        |
        v
 Scheduler selects an eligible node
        |
        v
 Kubelet on selected node
        |
        v
 Container runtime (typically via CRI)
        |
        v
 nginx-pod (Pod network namespace + nginx-container)
        |
        +-- Nginx listens on port 80 inside Pod
```

In an all-in-one environment, control-plane components and the application may run on the same host; the logical responsibilities are still different.

## 2. Container vs Pod vs Node vs Cluster

| Object | Mental model | Example |
| --- | --- | --- |
| **Container** | One process environment packaged from an image | `nginx-container` |
| **Pod** | Smallest deployable Kubernetes unit; one or more colocated containers sharing certain resources | `nginx-pod` |
| **Node** | Machine/VM that can host Pods | A K3s/RHEL VM node |
| **Cluster** | Collection of nodes and control-plane functionality managed through an API | Local K3s, Minikube, Kind, OpenShift |
| **Namespace** | Logical scope for resource names/access/policies | `default` |
| **Deployment** | Controller for desired replica count and rolling updates | Future Nginx deployment |
| **Service** | Stable access/discovery in front of suitable Pods | Future `nginx-service` |

**Important Pod behavior:** Containers in the same Pod share a network namespace/IP and can communicate over `localhost` on different ports. They may share explicitly mounted volumes, but do not automatically share the entire writable root filesystem. Podman Pods and Kubernetes Pods have related concepts but different control planes and lifecycles.

## 3. Read the exact instructor manifest

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

### `apiVersion: v1`

This means the API resource is in the core `v1` API group/version (not 'Kubernetes version 1'). A Deployment, for example, uses a different API group. The API server knows how to validate the fields for this resource type.

### `kind: Pod`

This resource declares a single Pod. A Pod is a workload object with a finite lifetime: scheduling, starting, running, failing/succeeding and deletion. For general user-facing services, a higher-level controller is normally preferable.

### `metadata.name`

`nginx-pod` identifies this Pod **within its namespace**. Names are not globally unique across all Kubernetes namespaces. Commands without `-n` use the active context's default namespace.

### `metadata.labels`

`app: nginx` is metadata used for filtering, organizing and later selecting Pods. A label by itself does not create a Service or tell the scheduler to deploy multiple replicas.

Useful optional inspection:

```bash
kubectl get pods -l app=nginx
kubectl get pod nginx-pod --show-labels
```

### `spec.containers`

Although this manifest contains only one Nginx container, a Pod can contain multiple cooperating containers (for example an app plus a helper/sidecar). They are scheduled together on the same node and share the Pod network namespace. Container-level names (`nginx-container`) differ from Pod-level names (`nginx-pod`).

### `image: nginx:latest`

Kubernetes pulls/uses an image as needed. `latest` can change between deployments, compromising reproducibility. The lesson deliberately uses it; in reviewed deployment manifests prefer a pinned version or immutable digest. Image-pull failures can show `ErrImagePull` or `ImagePullBackOff` in status/events.

### `containerPort: 80`

It describes an intended port in the container. It **does not publish** it to the host or internet. A Kubernetes Service, ingress/gateway, host-level configuration, or temporary `kubectl port-forward` is needed for particular access patterns. Do not confuse it with Podman's `-p 8080:80` flag.

## 4. Declarative configuration vs imperative commands

- **Declarative:** `kubectl apply -f simple-pod.yaml` describes a desired object; the API server stores the configuration and cluster controllers work toward it.
- **Imperative:** `kubectl run ...` sends a direct create request built from flags. Both use the same Kubernetes API, but YAML in version control is usually easier to review and reproduce.

`kubectl apply` can create, configure or leave the resource unchanged depending on existing state and field management. Re-running it does not necessarily start a second Pod. Not every Pod field can be freely changed in place; certain updates require a different object lifecycle.

**What `kubectl apply --dry-run=client` does not prove:** It does not schedule a Pod, pull the image, open a port, or verify that a node can run it.

## 5. What happens after `kubectl apply`?

1. **Client:** `kubectl` loads YAML and submits an API request using credentials/context from its kubeconfig (or bundled K3s configuration).
2. **API server:** Authenticates, authorizes/admission-checks, validates and stores the Pod object.
3. **Scheduler:** Finds a suitable node for an unscheduled Pod, taking resources and constraints into account.
4. **Kubelet:** Observes Pods assigned to its node and asks the runtime to create their containers and networking.
5. **Container runtime / networking:** Downloads image if needed; prepares filesystem and Pod network; starts Nginx.
6. **Status reporting:** Kubelet continuously reports observed Pod/container state to the API server; you inspect it with `get`, `describe`, and `logs`.

This is a conceptual path, not an actual timeline captured from the learner's cluster. A cluster may have admission controls, CRI plugins, CNI plugins and other steps.

## 6. Understand the output of `kubectl get pods`

```text
NAME        READY   STATUS    RESTARTS   AGE
nginx-pod   1/1     Running   0          10s
```

| Column | Engineering interpretation |
| --- | --- |
| `NAME` | Pod identifier in selected namespace |
| `READY` | Ready containers / total containers (not a generic application SLO) |
| `STATUS` | Human-readable status/reason; may show waiting reasons as well as Pod phase |
| `RESTARTS` | Restart counter for containers within the Pod |
| `AGE` | Pod object age |

**Nuance:** The `STATUS` column is not identical to the Pod object's `.status.phase`. `CrashLoopBackOff` and `ImagePullBackOff` are typically container waiting reasons presented by `kubectl`, not official Pod phases. Inspect detailed conditions/states rather than treating every visible status as a phase.

**`Running` is not the same as application health:** You may need readiness/liveness probes and actual HTTP checks for confidence. This lab doesn't configure probes.

## 7. Reading `describe`: reason before remediation

```bash
kubectl describe pod nginx-pod
```

Key sections:

- **Name/Namespace/Node:** Confirms you're inspecting the correct workload.
- **Status/IP:** Placement and network assignment, when available.
- **Containers:** Image, image ID, current/last state, exit code, restart count.
- **Conditions:** `PodScheduled`, `Initialized`, `ContainersReady`, `Ready` (depending on the Pod).
- **Events:** Scheduler failures, image pull errors, container start errors, policy denials.

### Three real failure patterns

**A. `Pending`** — The Pod hasn't completed scheduling/starting. Check events for `FailedScheduling`, insufficient resources, taints/tolerations, policy or volume issues. A single-node local cluster can be constrained by VM RAM/CPU.

**B. `ErrImagePull` / `ImagePullBackOff`** — Check the image reference, registry reachability, rate limiting, credentials and cluster DNS. A locally available Podman image on your laptop is not automatically in the Kubernetes node's runtime image store.

**C. `CrashLoopBackOff`** — The app process starts then repeatedly fails and is restarted with backoff. Check previous-container logs and exit reasons, not just current logs.

```bash
kubectl logs nginx-pod --previous
kubectl describe pod nginx-pod
```

An application can be `Running` but still return HTTP 500; status plus request-level validation is better than status alone.

## 8. Logs: what they can and cannot tell you

Instructor command:

```bash
kubectl logs nginx-pod
```

- Fetches logs for a container's stdout/stderr via Kubernetes node/runtime log support.
- For a one-container Pod, the container can often be inferred.
- For multi-container Pods, use `-c nginx-container` (or the relevant name).
- `-f` streams logs until stopped with `Ctrl+C`.
- `--previous` can retrieve logs from a prior terminated container instance when available.

```bash
kubectl logs -f nginx-pod
kubectl logs nginx-pod -c nginx-container
kubectl logs nginx-pod --previous
```

**Why logs may appear empty:** Traffic may not yet have reached Nginx; not every application logs every request or error to standard streams; logs can be rotated or ephemeral. Empty output does not inherently mean that the Pod failed.

For longer-term production investigation, logs are typically shipped to centralized observability systems rather than relying only on transient Pod logs.

## 9. Port forwarding: what is the actual connection?

Instructor command:

```bash
kubectl port-forward nginx-pod 8080:80
```

```text
Browser / curl on same machine as kubectl
          |
          | localhost:8080 (TCP)
          v
kubectl process holding a port-forward tunnel
          |
          | Kubernetes API / kubelet forwarding path
          v
Pod's port 80 ---> Nginx HTTP response
```

- `8080` is a temporary **local** listening port.
- `80` is the destination port inside the Pod.
- This forwards traffic only while the command/process is active.
- It is **not** a Kubernetes Service, NodePort, public load balancer or production ingress.
- Access is commonly restricted to loopback by default; avoid changing that to a public address for convenience.

### VirtualBox distinction

If Kubernetes lives in a RHEL VM but VS Code/browser is on Windows, then RHEL `localhost` and Windows `localhost` mean different machines. Running `curl http://localhost:8080` **within RHEL** tests the tunnel correctly. Access from Windows requires separate, deliberate forwarding/tunneling; the instructor's command alone doesn't make the VM service appear on the Windows loopback interface.

### How to test

**Terminal A:**

```bash
kubectl port-forward nginx-pod 8080:80
```

**Terminal B:**

```bash
curl http://localhost:8080
kubectl logs nginx-pod
```

The Nginx HTML response is a practical connectivity check. It does not prove high availability, durable storage or external internet exposure.

## 10. Bare Pod vs Deployment: an interview favorite

| Bare Pod in this lab | Deployment in a real service |
| --- | --- |
| One Pod object directly declared | Controller manages desired number of Pod replicas |
| Manual deletion leaves it absent | Controller usually creates replacement Pods to match desired state |
| No rolling rollout management | Deployment supports rolling updates/rollback mechanics |
| Great for learning Pod internals | Preferred for most stateless web services |
| Direct port-forward convenient for lab | A Service/Gateway/Ingress exposes an appropriate access path |

**Important nuance:** The kubelet normally can restart failing containers *inside* a bare Pod based on restart policy. This is not the same as a higher-level controller replacing a deleted Pod. If the node permanently fails, a standalone Pod is not automatically recreated on another node by a Deployment.

## 11. RHEL / K3s / OpenShift considerations

**K3s:** A lightweight Kubernetes distribution for local labs. `sudo k3s kubectl get nodes` is often usable immediately after installing K3s; the `sudo` wrapper/access setup is environment-dependent. To use plain `kubectl`, configure an appropriate kubeconfig and permissions; do not expose cluster credentials in GitHub.

**OpenShift:** The equivalent CLI is usually `oc`; OpenShift projects map to Kubernetes namespaces for most user workflows. Restricted security policies may reject or alter a container image that assumes particular privileges or file ownership. Don't claim all public images work unchanged on all OpenShift clusters.

**Podman:** Useful for local containers and images. Kubernetes nodes use a container runtime implementing CRI; Podman itself is not a substitute for Kubernetes API/scheduling. The existence of a Podman `nginx` image locally does not mean the Kubernetes cluster has pulled it.

**Security:** Avoid committing `~/.kube/config`, admin tokens, private certificates, service account secrets, or private addresses. Use least-privilege access and verified namespaces before modifying cluster resources.

## 12. Practical troubleshooting decision tree

```text
Is kubectl reaching the cluster?
  NO -> cluster-info, context, kubeconfig, permissions, cluster service.
  YES
   |
   v
Does nginx-pod exist?
  NO -> correct namespace, manifest path, apply output, authorization.
  YES
   |
   v
Does kubectl get pods show READY 1/1 and Running?
  NO -> describe/events, scheduling, image pull, container state, logs.
  YES
   |
   v
Can port-forward start on localhost:8080?
  NO -> port conflict, Pod not ready, wrong machine/CLI permissions.
  YES
   |
   v
Does curl localhost:8080 return Nginx HTML?
  NO -> wrong Pod/port, app not listening, timing/forwarding error.
  YES -> basic Pod deployment and local HTTP access verified.
```

Recommended inspection sequence:

```bash
kubectl config current-context
kubectl get nodes
kubectl get pods -o wide
kubectl describe pod nginx-pod
kubectl logs nginx-pod
kubectl get events --sort-by=.metadata.creationTimestamp
```

These are examples of a debugging workflow, not evidence that every command was run in the instructor exercise.

## 13. Engineering trade-offs: next-level thinking

1. **Image versioning:** An unpinned `nginx:latest` may change unexpectedly; use explicit versions/digests for predictable rollouts.
2. **Resources:** This exercise has no `resources.requests` or `resources.limits`. Production manifests usually require workload-appropriate limits/requests to support capacity management.
3. **Probes:** The exercise has no readiness/liveness/startup probes. HTTP reachability can be a useful lab verification, but proper probes serve different lifecycle purposes.
4. **Security context:** Principle of least privilege, filesystem permissions, restricted privileges and OpenShift compatibility need attention before production.
5. **Availability:** One bare Pod has no managed replicas; prefer a Deployment/Service architecture for most web apps.
6. **Networking:** `containerPort` is documentation for the Pod spec, not external exposure. Consider a Service and cluster network policy for intended communications.
7. **Observability:** Use logs, metrics, events and traces appropriate to environment; don't treat `Running` as proof that business functionality works.
8. **Configuration:** Avoid hard-coding passwords/secrets in images or public YAML. This sample Nginx Pod requires none.

## 14. Interview / review questions with precise answers

**Q1. What is the smallest deployable Kubernetes unit?**  
A **Pod**. A Pod includes one or more colocated containers with shared namespaces/resources according to its spec.

**Q2. Is a Pod just a Docker/Podman container?**  
No. A Pod is a Kubernetes resource and can contain multiple containers, its own metadata/status, and shared network/storage configuration.

**Q3. What does `apiVersion: v1` mean?**  
The Pod resource uses the core `v1` Kubernetes API version.

**Q4. What is a label used for?**  
Selecting, grouping, querying and organizing resources. Labels alone do not create Services or replicas.

**Q5. What does `kubectl apply -f` do?**  
Submits/declaratively manages the resource specified in a file through the Kubernetes API.

**Q6. Does `kubectl apply` directly run the container?**  
No. The control plane schedules the Pod and the node's kubelet/runtime runs its containers.

**Q7. What does `1/1` mean in `kubectl get pods`?**  
One of one declared containers is currently ready.

**Q8. Is `Running` proof that Nginx serves requests correctly?**  
No. Inspect readiness and test the application; use proper probes in managed workloads.

**Q9. Why can a Pod stay `Pending`?**  
Insufficient/unsuitable nodes/resources, constraints or setup failures; inspect describe/events for the actual reason.

**Q10. Why does a Pod show `ImagePullBackOff`?**  
The runtime cannot pull the requested image; examine the image ref, registry/network/authentication and events.

**Q11. What's the difference between `describe` and `logs`?**  
`describe` focuses on object configuration/status/events; `logs` shows output from container processes.

**Q12. How do you check previous crash logs?**  
`kubectl logs nginx-pod --previous` if a previous container instance exists.

**Q13. Does `containerPort: 80` make port 80 publicly accessible?**  
No. It does not publish a host port or create a Service.

**Q14. What does `8080:80` mean in `port-forward`?**  
Local port 8080 forwards to the Pod's port 80 while the tunnel is active.

**Q15. Why might Windows `localhost:8080` not work when `kubectl` runs in a RHEL VM?**  
Each OS has its own loopback interface. Test on the machine where the tunnel listens, or set up secure forwarding.

**Q16. What happens if you delete this standalone Pod?**  
It remains deleted unless some other controller or actor recreates it; a Deployment manages replacements.

**Q17. If Nginx crashes, can its container restart?**  
Yes, according to Pod restart behavior/policy, but restarting a container is distinct from recreating a deleted Pod.

**Q18. Why should production avoid `:latest`?**  
Mutable tags reduce reproducibility and make rollback/debug comparisons harder.

**Q19. How do `kubectl` and `oc` relate?**  
Both interact with Kubernetes/OpenShift APIs; `oc` additionally supports OpenShift-specific workflows.

**Q20. Is this manifest production ready?**  
No. It's a teaching example: no Deployment, replicas, Service, probes, resource requests/limits or reviewed security settings.

## 15. Review the original lab, end to end

**Task 1:** Create [`simple-pod.yaml`](simple-pod.yaml) using the instructor's exact API version, kind, metadata and Nginx spec.  
**Task 2:** Run `kubectl apply -f simple-pod.yaml`, verify with `kubectl get pods`, and investigate `Pending` / `CrashLoopBackOff` with `describe` / `logs`.  
**Task 3:** Run `kubectl describe pod nginx-pod` and `kubectl logs nginx-pod`. Optionally run `kubectl port-forward nginx-pod 8080:80` and open `http://localhost:8080`.

**Real result status:** Learner confirmed completion. The documentation preserves the reproducible steps but does not attach independent runtime proof.

## 16. Next learning steps (aligned with instructor)

- Create a Pod containing two cooperating containers and observe their shared network namespace.
- Explore `restartPolicy`, Pod phases, readiness/liveness/startup probes and scheduling events.
- Convert the bare Pod concept into a `Deployment` with a `Service` and compare lifecycle behavior.

## References

- [Kubernetes Pods](https://kubernetes.io/docs/concepts/workloads/pods/)
- [Kubernetes Pod lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
- [kubectl reference](https://kubernetes.io/docs/reference/kubectl/)
- [OpenShift documentation](https://docs.openshift.com/)

**Maintained by:** Hafiz Mohammad Sunasara.
