# Lab 19 — Deploying StatefulSets

> **Track:** Domain 5 → Linux and Open Source → Red Hat 1  
> **Status:** **Completed — self-reported** (learner confirmed completing the entire practical lab)  
> **Environment:** Kubernetes or OpenShift cluster with `kubectl`/`oc` and dynamic or preprovisioned persistent storage  
> **Evidence:** Reproducible manifests and expected verification steps. This repository does **not** claim that the command outputs below are preserved terminal logs, or that an independent reviewer ran these commands.

**Start here:** This is the complete practical runbook covering every task in the instructor-provided exercise. For deeper engineering reasoning, failure modes, storage lifecycle, DNS, HA limitations, and interviews, see **[DEEP-DIVE.md](DEEP-DIVE.md)**.

## Objectives

1. Understand the purpose of Kubernetes/OpenShift **StatefulSets**.
2. Define and deploy a **MySQL StatefulSet** using a YAML manifest.
3. Verify that Pods have **stable identities** and **per-Pod persistent storage** even when a Pod is replaced.

## Prerequisites and environment validation

- Running Kubernetes or OpenShift cluster, such as Minikube, Kind, CRC/OpenShift Local, or a training cluster.
- Working `kubectl` (or appropriate `oc`), configured to access the cluster.
- Knowledge of Pods, Services, PV/PVC, YAML and cluster namespaces.
- Working **StorageClass** called `standard` for the unmodified instructor manifest. If unavailable, change the StorageClass name to one that actually exists **before deployment**.
- Enough memory and disk for **two MySQL 8.0 instances**, each requesting **1Gi** of persistent storage.

Useful prechecks (additional diagnostics; not replacements for the instructor steps):

```bash
kubectl version --client
kubectl cluster-info
kubectl get nodes
kubectl get storageclass
kubectl config current-context
```

> **Security and compatibility:** The password `password` below is the **instructor's disposable lab example**, committed to source solely to reproduce the exercise. **Never reuse it in real environments.** Production credentials belong in Kubernetes Secrets or a managed secret system, subject to your organization's policies. MySQL and CSI/storage security restrictions can also affect OpenShift clusters. The example is **not production ready**.

---

## Task 1 — Write a StatefulSet manifest

**Objective:** Describe a stateful MySQL application with automatically created **PersistentVolumeClaims (PVCs)**.

### Step 1: Create `mysql-statefulset.yaml`

```bash
nano mysql-statefulset.yaml
```

Paste the instructor's manifest, also provided as the executable sibling file **[mysql-statefulset.yaml](mysql-statefulset.yaml)**:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: "mysql"
  replicas: 2
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: "password"
        ports:
        - containerPort: 3306
          name: mysql
        volumeMounts:
        - name: mysql-persistent-storage
          mountPath: /var/lib/mysql
  volumeClaimTemplates:
  - metadata:
      name: mysql-persistent-storage
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: "standard"
      resources:
        requests:
          storage: 1Gi
```

### What every important field does

| Field | Meaning |
| --- | --- |
| `apiVersion: apps/v1`, `kind: StatefulSet` | Kubernetes StatefulSet workload API. |
| `metadata.name: mysql` | Controller name; generated Pods are ordinarily `mysql-0`, `mysql-1`. |
| `spec.serviceName: mysql` | Associates Pod network identity with the **headless Service named `mysql`**, which you must create. |
| `replicas: 2` | Requests two distinct MySQL Pods, **not** MySQL replication. |
| `selector.matchLabels` / `template.metadata.labels` | Must match so the StatefulSet controls the correct Pods. |
| `MYSQL_ROOT_PASSWORD` | Sets the root password when a new database data directory is initialized; not suitable for production as plaintext. |
| `volumeMounts` | Mounts each Pod's corresponding PVC at MySQL's data directory `/var/lib/mysql`. |
| `volumeClaimTemplates` | Makes one independent PVC per Pod from the given template. |
| `ReadWriteOnce` | Storage can mount read/write on one node; it does **not** imply a single process or Pod access guarantee. |
| `storageClassName: standard` | Requires a matching StorageClass or matching preprovisioned volume; environment-specific. |
| `storage: 1Gi` | Each Pod requests 1Gi, i.e., two claims of 1Gi each. |

The actual PVC names follow `<claim-template-name>-<pod-name>`:

```text
mysql-persistent-storage-mysql-0
mysql-persistent-storage-mysql-1
```

### Instructor's validation command — preserve exactly

```bash
kubectl apply -f mysql-statefulset.yaml --dry-run=client
```

**Expected:** The client successfully processes the manifest, e.g. an `... created (dry run)` message. This is **not** proof that Pods can run, that `standard` exists, or that a PVC will bind. For server-side checks where supported, an optional additional check is:

```bash
kubectl apply --dry-run=server -f mysql-statefulset.yaml
```

> **Common prerequisite mismatch:** If `kubectl get storageclass` lists `local-path`, `managed-csi`, or another actual class but **not** `standard`, edit `storageClassName` in `mysql-statefulset.yaml` before creating the StatefulSet. Do **not** invent a `standard` class name.

---

## Task 2 — Deploy the stateful application

**Objective:** Create the StatefulSet and its governing headless Service, then verify Pods and PVCs.

### Step 1: Apply the StatefulSet (instructor order)

```bash
kubectl apply -f mysql-statefulset.yaml
```

Kubernetes begins reconciling Pods and PVCs. The instructor creates the governing Service next. **Operational improvement:** create the headless Service **before** the StatefulSet in a fresh cluster, because the service is required for predictable Pod DNS identities. Either way, do not skip either resource.

### Step 2: Create `mysql-service.yaml` and apply it

```bash
nano mysql-service.yaml
```

Instructor's headless Service, preserved exactly as **[mysql-service.yaml](mysql-service.yaml)**:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql
spec:
  clusterIP: None
  ports:
  - port: 3306
    name: mysql
  selector:
    app: mysql
```

```bash
kubectl apply -f mysql-service.yaml
```

The `clusterIP: None` line makes this a **headless Service**. It enables DNS to expose matching ready Pod IPs and per-Pod identities, rather than a single virtual service IP. Headless DNS typically returns **ready endpoints only** unless configured otherwise.

### Step 3: Verify resources (instructor command)

```bash
kubectl get statefulset,pods,pvc
```

**Expected resources, illustrative—not captured execution:**

```text
StatefulSet: mysql, desired replicas 2, eventually READY 2/2
Pods:        mysql-0 and mysql-1, eventually Running/Ready
PVCs:        mysql-persistent-storage-mysql-0 and mysql-persistent-storage-mysql-1, eventually Bound
```

The course's shortened example `pvc/mysql-0` / `pvc/mysql-1` is **not** the actual naming generated by this claim template.

**Useful additional validation:**

```bash
kubectl rollout status statefulset/mysql --timeout=300s
kubectl get svc mysql
kubectl get pvc -o wide
kubectl describe statefulset mysql
```

Under the default `OrderedReady` strategy, `mysql-1` may not be created until `mysql-0` becomes Ready.

---

## Task 3 — Verify persistent storage and network identity

**Objective:** Show Kubernetes Pod replacement retains the Pod's storage identity; verify networking through DNS.

### Step 1: Check stable Pod names (instructor command)

```bash
kubectl get pods -l app=mysql -o wide
```

**Expected names:** `mysql-0`, `mysql-1`. Pod IPs may change on replacement, while StatefulSet Pod names stay consistent.

### Step 2: Create data in the first MySQL instance (instructor command)

```bash
kubectl exec -it mysql-0 -- mysql -uroot -ppassword -e "CREATE DATABASE lab_test;"
```

**Expected:** Exit successfully. This database is saved to **mysql-0's own PVC**, not automatically copied to mysql-1. This exercise checks creation of the `lab_test` **database**, not table-level content.

**Optional extra evidence before deletion:**

```bash
kubectl exec mysql-0 -- mysql -uroot -ppassword -e "SHOW DATABASES;"
kubectl get pvc mysql-persistent-storage-mysql-0
```

### Step 3: Delete `mysql-0` (instructor command)

```bash
kubectl delete pod mysql-0
```

The StatefulSet controller should reconcile a replacement with the **same Pod name** and the corresponding existing PVC. The new Pod's IP, UID and node may be different.

**Wait for recovery before running the next instructor command:**

```bash
kubectl get pods -l app=mysql -w
```

Press `Ctrl+C` to exit the watch after `mysql-0` is Ready, then optionally:

```bash
kubectl wait --for=condition=Ready pod/mysql-0 --timeout=300s
```

### Step 4: Verify recovered data (instructor command)

```bash
kubectl exec -it mysql-0 -- mysql -uroot -ppassword -e "SHOW DATABASES;"
```

**Success criterion:** `lab_test` appears in the output **after the replacement Pod comes up**. This demonstrates persistence across Pod recreation when its volume is intact and reattached. It does not establish backup durability, restore capability, HA failover, or MySQL replication.

### Step 5: Verify DNS resolution (instructor command)

```bash
kubectl run -it --rm --image=busybox:1.28 test --restart=Never -- nslookup mysql
```

This looks up the **headless Service `mysql`**, not necessarily every individual Pod DNS record. It commonly resolves to the IPs of the currently Ready MySQL Pod endpoints.

**Stronger optional checks for stable, per-Pod identities:**

```bash
kubectl run -it --rm --image=busybox:1.28 dns-mysql0 --restart=Never -- nslookup mysql-0.mysql
kubectl run -it --rm --image=busybox:1.28 dns-mysql1 --restart=Never -- nslookup mysql-1.mysql
```

In a non-default namespace, the full form is `<pod-name>.mysql.<namespace>.svc.cluster.local` (subject to your cluster domain configuration). DNS may take time to update; verify Service and EndpointSlices if resolution fails.

---

## Troubleshooting — instructor steps and engineer additions

### A. PVCs remain `Pending`

Instructor's command:

```bash
kubectl get storageclass
```

For **Minikube-only** setups, the instructor recommends:

```bash
minikube addons enable storage-provisioner
```

**Important qualification:** Enabling a provisioner is not by itself proof that the manifest's requested `standard` StorageClass exists or is configured properly. Recheck `kubectl get storageclass` and PVC events:

```bash
kubectl describe pvc mysql-persistent-storage-mysql-0
kubectl get pvc
```

Usual causes: misspelled/absent StorageClass, no matching PV, provisioner not healthy, quota or capacity shortage, or scheduler constraints.

### B. Pod fails to start, or second Pod never appears

Instructor's command:

```bash
kubectl logs mysql-0
```

Additional checks:

```bash
kubectl describe pod mysql-0
kubectl get pods -l app=mysql
kubectl get events --sort-by=.lastTimestamp
```

Look for image pull errors, permissions, inaccessible persistent disks, MySQL initialization problems, container startup failures, or inadequate resources. `mysql-1` can wait for `mysql-0` readiness because of `OrderedReady`.

### C. Can't connect to MySQL

- Verify Pod **Ready**, then test `SHOW DATABASES;` within the Pod.
- Ensure Pod and Service labels/selectors match `app: mysql`.
- Do not assume `mysql-1` replicated `mysql-0`'s database. They are **independent MySQL instances** in this lab.
- Avoid publishing database port 3306 outside the cluster in a disposable learning lab.

### D. DNS or hostnames unexpected

```bash
kubectl get svc mysql -o yaml
kubectl get endpointslice -l kubernetes.io/service-name=mysql
kubectl get pods -l app=mysql -o wide
```

Check that Service exists, cluster DNS is healthy, and Pods have Ready endpoints.

---

## Cleanup — instructor command (preserved exactly)

```bash
kubectl delete -f mysql-statefulset.yaml -f mysql-service.yaml
```

> **Data safety:** This typically deletes the StatefulSet and Service but **retains** their per-Pod PVCs by default. Never delete PVCs as a casual cleanup step; deletion may irreversibly remove the backing storage depending on the reclaim policy. If re-running the lab, retained MySQL data may already exist.

Optional inspection after cleanup (safe; does not delete data):

```bash
kubectl get statefulset,pods,pvc,svc
```

If clean startup is required for a new attempt, determine exactly which resources to remove, understand the reclaim policy and preserve any needed data first.

---

## Learner completion record and evidence honesty

- **Task 1:** Instructor StatefulSet YAML and dry-run covered.
- **Task 2:** StatefulSet + headless Service creation, resource checks covered.
- **Task 3:** Per-Pod identity, create/delete/recreate persistence test and DNS checks covered.
- **Troubleshooting/cleanup:** All instructor steps are included.
- **Learner's status:** **Completed — self-reported**, as confirmed in conversation.
- **Independent evidence:** No original CLI transcript, real PVC output, screenshots or cluster metadata was supplied for this file. The snippets marked *Expected* are **illustrative**.

If available, attach **real** evidence separately: `kubectl get statefulset,pods,pvc`, the MySQL database check **after** the replacement, and headless/per-Pod DNS output. Do not publish kubeconfigs or credentials.

## Quick knowledge check

1. Why choose a StatefulSet instead of a Deployment for individually identified Pods?
2. Why do `mysql-0` and `mysql-1` get separate PVCs?
3. What exactly survives `kubectl delete pod mysql-0`?
4. Is a headless Service a load-balanced single IP?
5. Do two MySQL Pods automatically replicate their data?
6. Why must the StorageClass match the actual cluster?
7. What gets removed by the instructor's cleanup command, and what ordinarily remains?

**Continue:** [Engineering Deep Dive](DEEP-DIVE.md) · [Lab Index](../LABS-INDEX.md) · [Proof of Work](../../evidence/PROOF-OF-WORK.md)

### Primary technical references

- [Kubernetes StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [Kubernetes StatefulSet API](https://kubernetes.io/docs/reference/kubernetes-api/apps/stateful-set-v1/)
- [Kubernetes replicated MySQL tutorial](https://kubernetes.io/docs/tasks/run-application/run-replicated-stateful-application/)
