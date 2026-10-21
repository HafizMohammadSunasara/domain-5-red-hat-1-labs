# Lab 19 — Deep Dive: StatefulSet Identity, Persistent Storage, Kubernetes DNS and MySQL

> **Track:** Domain 5 → Linux and Open Source → Red Hat 1  
> **Companion:** [Complete practical runbook](README.md) · [StatefulSet manifest](mysql-statefulset.yaml) · [Headless Service manifest](mysql-service.yaml)  
> **Status:** Completed — **self-reported**, not independently validated by stored runtime logs. Technical examples below are illustrative unless explicitly identified as commands to execute.

## 1. What production engineering problem does a StatefulSet solve?

A conventional Kubernetes **Deployment** manages fungible Pods: individual Pod identity is usually not important, and replacement Pods typically get generated names. This is ideal for many stateless applications. Stateful systems—databases, queues, clustered services—often need *stable per-member identities* and *predictable storage association*.

A **StatefulSet** gives managed Pods stable **names/ordinals** (`mysql-0`, `mysql-1`), a stable network naming pattern through a governing headless Service, and storage claims associated with those ordinal identities. A Pod's **IP/UID/node may change** when replaced. The Pod's name and associated PVC normally persist.

**Core rule:** Kubernetes preserves the desired identity and storage association; the actual application must still be designed to use that storage reliably.

## 2. Visual mental model

```text
                Kubernetes API / StatefulSet controller
                               |
                    StatefulSet: mysql
                     serviceName: mysql
                        replicas: 2
                               |
                 Governing headless Service
                   mysql (clusterIP: None)
                         /          \
                        /            \
          mysql-0.mysql              mysql-1.mysql
          +-----------+              +-----------+
          | mysql-0   |              | mysql-1   |
          | MySQL 8.0 |              | MySQL 8.0 |
          +-----------+              +-----------+
                 |                          |
        /var/lib/mysql                /var/lib/mysql
                 |                          |
       PVC: mysql-persistent-       PVC: mysql-persistent-
            storage-mysql-0              storage-mysql-1
                 |                          |
           PV / volume A              PV / volume B

     NO MySQL primary/replica configuration in this lab.
     Data on mysql-0 is NOT automatically copied to mysql-1.
```

## 3. Read the manifest like a Kubernetes engineer

### Controller and Pod identity

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: "mysql"
  replicas: 2
```

`apps/v1` is the stable API for StatefulSet resources. StatefulSet named `mysql` normally creates `mysql-0` then `mysql-1` with default ordinal start 0. `serviceName: mysql` references a **separate headless Service** resource; the StatefulSet does not generate the Service by itself.

### Selector and template labels

```yaml
selector:
  matchLabels:
    app: mysql
template:
  metadata:
    labels:
      app: mysql
```

The selector tells the controller which Pods belong to it. It must match the Pod template labels. The headless Service uses the same selector to identify endpoints.

### Container, database initialization, and mount

```yaml
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
```

- MySQL's data directory `/var/lib/mysql` is mounted from the Pod's corresponding PVC.
- MySQL's first-time initialization depends on the state of that data directory: changing `MYSQL_ROOT_PASSWORD` in an existing populated volume does **not** automatically change the already-initialized DB user's password.
- `containerPort: 3306` is descriptive metadata, **not** a host port publication.
- Plaintext database credentials in YAML/command history are unacceptable for real production; use Secret-backed variables or a vetted secrets manager and proper RBAC.
- `mysql:8.0` is an instructor-specified moving patch-version tag. For reliable promotion/change control, pin a tested patch tag or digest.

### Storage claims: template versus a mounted volume

```yaml
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

- StatefulSet creates **one PVC per Pod ordinal** from this template, named `<template-name>-<statefulset-pod-name>`.
- `ReadWriteOnce` (RWO) means mount read/write by one *node*; it does not guarantee exclusive mount by a single Pod. Newer clusters may support `ReadWriteOncePod` for stricter single-Pod semantics where appropriate and supported.
- StorageClass specifies *how storage is provisioned*. The value `standard` is a Minikube-style example, **not universal**.
- PVC `Bound` means Kubernetes matched/provisioned storage. It **does not** by itself prove MySQL successfully read/wrote data.
- Two replicas × one 1Gi claim each = **2Gi requested storage**, not 2Gi of copied/replicated database contents.

### PV, PVC, StorageClass, mount — separate layers

| Term | Purpose |
| --- | --- |
| StorageClass | Describes a storage provisioner and provisioning policies. |
| PVC | Names a requested storage capacity/access mode. |
| PV | Cluster-level provisioned or pre-existing persistent volume. |
| `volumeClaimTemplates` | Creates and associates distinct PVCs for StatefulSet Pod ordinals. |
| `volumeMounts` | Makes that storage accessible to MySQL at `/var/lib/mysql`. |

Different storage backends provide different guarantees. A local-path volume on one node is not equivalent to replicated regional block storage. StatefulSet alone does **not** make data resilient to host/disk loss.

## 4. Why a headless Service, and how stable DNS works

Instructor's Service:

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

`clusterIP: None` produces a *headless* Service. Instead of assigning the Service one load-balanced virtual IP, Kubernetes DNS returns endpoint data for the matching Pods (commonly Ready endpoints).

Inside the namespace, individual names are usually:

```text
mysql-0.mysql
mysql-1.mysql
mysql-0.mysql.<namespace>.svc.cluster.local
mysql-1.mysql.<namespace>.svc.cluster.local
```

**Critical nuance:**

- `nslookup mysql` resolves the **Service name**, often yielding the Ready endpoint IPs. It does **not** prove every member's individual DNS record resolves.
- `nslookup mysql-0.mysql` checks an individual member identity. A Pod's IP can change after recreation while its DNS *name* is stable.
- Service must exist and match the Pod labels. DNS availability follows readiness and endpoint updates. A not-Ready Pod may temporarily not appear in normal Service DNS, unless configured with `publishNotReadyAddresses` for applicable bootstrap scenarios.
- The default Kubernetes cluster domain is commonly `cluster.local`, but isn't guaranteed in all clusters.

## 5. OrderedReady vs Parallel (and what 'replicas: 2' does not do)

By default, StatefulSets use **OrderedReady** Pod management:

1. Create `mysql-0`; wait until it becomes Running and Ready.
2. Create `mysql-1`; wait for its readiness.
3. Scaling down usually proceeds in reverse ordinal order.

`podManagementPolicy: Parallel` relaxes ordering during Pod creation/termination for appropriate apps. It does not turn independent databases into a replication cluster.

**Important:** `replicas: 2` means **two MySQL server processes, two Pods, two persistent data directories.** It does **not** configure primary selection, asynchronous replication, quorum, clustering, backups, read routing, or failover. For actual MySQL HA/replication, use a properly configured topology, database operator, managed database service, or the more complex upstream MySQL StatefulSet reference with replication sidecars/configuration.

## 6. Exactly what happens during the persistence test

### Before deletion

```bash
kubectl exec -it mysql-0 -- mysql -uroot -ppassword -e "CREATE DATABASE lab_test;"
```

MySQL creates metadata in `mysql-0`'s database data directory. This directory is backed by `mysql-persistent-storage-mysql-0`.

### Delete the Pod, not its PVC

```bash
kubectl delete pod mysql-0
```

The controller observes that the desired ordinal `mysql-0` is missing; Kubernetes creates a replacement. The replacement inherits the **Pod name** and is associated with the previously provisioned PVC for that ordinal. Its container is freshly created; the **data directory remains** when storage is healthy.

### Verify after it is Ready

```bash
kubectl wait --for=condition=Ready pod/mysql-0 --timeout=300s
kubectl exec -it mysql-0 -- mysql -uroot -ppassword -e "SHOW DATABASES;"
```

Seeing `lab_test` again supports **Pod-recreation persistence on an intact volume**. It does not demonstrate tolerance of a lost backing PV, cross-zone failover, disaster recovery, replication, nor actual independent backup restores.

Why doesn't the other Pod automatically have `lab_test`? Because it has **another PVC** and there is no replication configuration.

## 7. Design limitations and security hazards

1. **Plaintext passwords:** Lab values are not for real workloads. Use Kubernetes Secret references with RBAC and consider secret rotation, encryption, and least privilege. Remember: a Kubernetes Secret is not automatically a fully managed encrypted vault in every cluster.
2. **No readiness/liveness probes:** The instructor workload doesn't define probes. For robust service readiness, use appropriate health/readiness probes and database-aware initialization.
3. **Storage availability:** RWO access and dynamic provisioning don't guarantee durable multi-node recovery; understand the CSI backend, zones, snapshots and reclaim policies.
4. **MySQL data consistency:** Don't assume copying a hot data directory provides a safe backup. Use a consistent MySQL backup or snapshot strategy and periodically test restores.
5. **Resource management:** No CPU/memory requests or limits are set; resource-constrained labs may run slowly or fail. Size these thoughtfully in actual clusters.
6. **Not HA:** Two independent MySQL Pods are not a synchronized HA database. Treat the exercise as a Kubernetes storage/identity demonstration, not a deployable MySQL cluster architecture.
7. **StatefulSet deletion:** PVCs normally remain (default `Retain`). Optional `persistentVolumeClaimRetentionPolicy` can change behavior on deletion or scale-down, depending on the manifest/cluster. Reclaim policy of the *PV* is a separate concern.
8. **Data safety after cleanup:** Deleting a PVC may eventually delete its backing storage. Confirm and back up data before manual deletion.

## 8. Debugging playbook: symptom → cause → commands → next step

| Symptom | Likely area | Start here | Correct response |
| --- | --- | --- | --- |
| PVC `Pending` | StorageClass/provisioner/capacity | `kubectl get storageclass`; `kubectl describe pvc mysql-persistent-storage-mysql-0` | Match real StorageClass, inspect events, quota, CSI provisioning. |
| `mysql-0` `Pending` | Scheduling/volume binding | `kubectl describe pod mysql-0` | Check node resources, affinity, PVC events. |
| `mysql-0` `CrashLoopBackOff` | MySQL initialization, permissions, data files | `kubectl logs mysql-0`; `kubectl logs mysql-0 --previous` | Identify actual crash; don't destroy PVC as a guess. |
| `mysql-1` missing | OrderedReady gate | `kubectl get pods`; `kubectl describe pod mysql-0` | Make `mysql-0` Ready; second ordinal may be waiting. |
| DNS `mysql-0.mysql` fails | Service/readiness/cluster DNS | `kubectl get svc mysql`; `kubectl get endpointslice -l kubernetes.io/service-name=mysql` | Check Service selection and Pod readiness. |
| Database `lab_test` missing after recovery | Different PVC/namespace/data folder | `kubectl get pvc`; `kubectl describe pod mysql-0` | Check exact PVC/volume mapping; do not claim persistence without query output. |
| Password appears wrong after restart | Reused initialized MySQL volume | `kubectl logs mysql-0`; inspect initialized DB state | Environment variable may only apply during first initialization; avoid blind resets. |
| `standard` missing | Environment mismatch | `kubectl get storageclass` | Substitute actual class before apply. |

For Minikube users, the course suggests `minikube addons enable storage-provisioner`, but the class and dynamic provisioner must still be verified afterwards; this command isn't applicable to every lab environment.

## 9. Practical engineering follow-ups (optional, not claimed complete)

### A. Verify per-Pod isolation explicitly

```bash
# For illustration only: query the SECOND database instance
kubectl exec mysql-1 -- mysql -uroot -ppassword -e "SHOW DATABASES;"
```

If the lab was unmodified, `mysql-1` would not automatically contain `lab_test` created only on `mysql-0`. The exact data on each instance depends on whether they were initialized with existing PVCs or used for other experiments.

### B. Observe PVC mapping

```bash
kubectl get pvc -o wide
kubectl describe pod mysql-0
kubectl describe pod mysql-1
```

### C. Practice controlled scaling without deleting data

```bash
kubectl scale statefulset/mysql --replicas=1
kubectl get pods,pvc
kubectl scale statefulset/mysql --replicas=2
```

Pods change as replicas change, but associated claims ordinarily remain unless a retention policy changes that behavior. Practice only in an isolated lab namespace.

### D. Upgrade strategy concepts

- `updateStrategy: RollingUpdate` is a StatefulSet update strategy.
- `podManagementPolicy: OrderedReady` is the default; `Parallel` may suit workloads not requiring ordinal sequencing.
- Startup/readiness probes, storage preflight, backups, backup-restore drills and disruption planning must be separately designed.

## 10. Interview questions with concise answers

1. **What is a StatefulSet?** A Kubernetes controller giving Pods stable network/storage identities and ordered management.
2. **How does it differ from a Deployment?** Stable unique ordinal identities and per-member PVC association vs broadly replaceable Pod identities.
3. **Why is `serviceName` required?** It names the governing Service that determines the Pods' DNS network domain.
4. **What is a headless Service?** A Service with `clusterIP: None` that exposes backing endpoint identities through DNS instead of a single virtual ClusterIP.
5. **Are `mysql-0` and `mysql-1` replicas of the same data?** No, not without MySQL replication configuration.
6. **What creates PVCs?** `volumeClaimTemplates` in the StatefulSet.
7. **How are per-Pod claim names formed?** `<template-name>-<pod-name>`.
8. **What does `ReadWriteOnce` mean?** A single node can mount volume read-write, not necessarily one Pod exclusively.
9. **What remains after deleting a Pod?** The StatefulSet reconstructs it; PVCs normally persist if not explicitly deleted.
10. **Can a Pod's IP change?** Yes; stable Pod *names* and DNS naming pattern are the guarantee, not stable Pod IP.
11. **Why would PVCs remain Pending?** Missing StorageClass, no provisioner/PV, capacity, quota or topology/scheduling constraints.
12. **What if `standard` is unavailable?** Choose a real provisioned class and adjust the manifest.
13. **What does `OrderedReady` do?** Create Pods in order, waiting for each to become Ready before proceeding to the next.
14. **Why might `mysql-1` not start?** `mysql-0` not ready can block it under `OrderedReady`.
15. **Is `kubectl apply --dry-run=client` sufficient?** No, it doesn't ensure working storage, scheduling or DB readiness.
16. **How do you check database retention?** Create data; delete `mysql-0`; wait for replacement; query same DB on recreated Pod.
17. **Does the headless service guarantee every Pod answers DNS when unready?** No, default DNS usually reflects ready endpoints; other configurations can alter this.
18. **Why isn't plaintext password OK?** It can leak via repository, manifests, history and cluster API access.
19. **Does deleting the StatefulSet delete its PVCs?** Not by default; PVC retention policies can change behavior.
20. **Does PVC persistence replace a backup?** No—backups are needed for corruption, operator mistakes, lost volumes and disaster recovery.
21. **What's the difference between `kubectl logs` and `describe`?** Logs show container stdout/stderr; describe includes Pod status, scheduling, volume info and events.
22. **What enables true MySQL HA?** Application-level replication/failover design or a specialized operator/managed database, not a StatefulSet alone.

## 11. Optional next-project design: from educational lab to reliable database platform

**Do not confuse these improvements with the completed course tasks.** A more realistic project would specify:

- Secret-backed database credentials, access controls and network restrictions.
- A MySQL-aware controller/operator or explicitly configured and tested replication topology.
- Probes, resource requests/limits and deliberate storage policies.
- Separate logical/physical backups with verified restore procedures and recovery objectives.
- Monitoring, alerts, failure testing, migrations and documented rollbacks.

That project would be substantially different from this minimal instructor exercise.

## 12. Evidence and references

The learner reported successful completion of all tasks, but this folder includes **no captured `kubectl` outputs, screenshots, actual PVC IDs, MySQL query results, DNS traces, or performance results**. Reproducible manifests and diagnostic instructions are provided; expected outcomes are **not** represented as historical evidence.

**Official references:**

- Kubernetes StatefulSets: https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/
- StatefulSet API: https://kubernetes.io/docs/reference/kubernetes-api/apps/stateful-set-v1/
- Headless Service and real replicated MySQL tutorial: https://kubernetes.io/docs/tasks/run-application/run-replicated-stateful-application/
- Kubernetes StorageClass: https://kubernetes.io/docs/concepts/storage/storage-classes/
- Kubernetes PVCs: https://kubernetes.io/docs/concepts/storage/persistent-volumes/

**Back to:** [Practical runbook](README.md) · [Lab Index](../LABS-INDEX.md)
