# Lab 11 — Engineering Deep Dive: Stateful Database Containers

**Domain 5 → Linux and Open Source → Red Hat 1**  
**Companion:** [Full practical README — every instructor command and task](README.md)  
**Scope:** MySQL 8.0 (learner-reported Tasks 1–2), PostgreSQL 13 (optional, not yet explicitly confirmed).  
**Evidence policy:** Examples are educational; no unavailable logs, terminal outputs, benchmarks, or test results are claimed.

## Table of contents

1. [What makes a container stateful?](#what-makes-a-container-stateful)
2. [Where the data really lives](#where-the-data-really-lives)
3. [Without a persistent mount](#without-a-persistent-mount)
4. [MySQL: initial setup and reinitialization](#mysql-initial-setup-and-reinitialization)
5. [Why Task 2 proves persistence](#why-task-2-proves-persistence)
6. [PostgreSQL: same goal, different engine](#postgresql-same-goal-different-engine)
7. [Named volumes vs bind mounts](#named-volumes-vs-bind-mounts)
8. [SELinux and filesystem ownership](#selinux-and-filesystem-ownership)
9. [Security controls](#security-controls)
10. [Migration and backups](#migration-and-backups)
11. [Failure scenarios and troubleshooting](#failure-scenarios-and-troubleshooting)
12. [Real-world architecture and interview questions](#real-world-architecture-and-interview-questions)
13. [What's actually proven](#whats-actually-proven)

---

## What makes a container stateful?

A **stateless** component can often start with only its image, configuration, and external dependencies. Its disposable runtime filesystem does not hold the authoritative business records.

A **stateful** component—such as MySQL or PostgreSQL—must retain meaningful changes over time: records, tables, transaction logs, and database metadata. Those changes must remain accessible to a replacement container. A containerized database can be a perfectly valid learning or production architecture, but the lifecycle of the container and the lifecycle of its data must be designed separately.

The practical question in this lab is **not** merely "does a container restart?" It is:

> Can we destroy a specific container, create a different container from the image, and still read the **same previously committed database row**?

This is a narrow but useful durability experiment. It does not test recovery from a damaged database or a failed host.

## Where the data really lives

The lab's MySQL mapping:

```text
          RHEL/WSL2 HOST                      CONTAINER
  ~/stateful-lab/mysql-data        <->        /var/lib/mysql
          ┌─────────────┐                    ┌─────────────┐
          │ database    │  bind mount        │ mysqld      │
          │ files       │ <================> │ reads/writes│
          └─────────────┘                    └─────────────┘
            retained                         replaceable
```

PostgreSQL 13 mapping:

```text
~/stateful-lab/pg-data            <->  /var/lib/postgresql/data
```

This is a **bind mount**: `-v HOST_PATH:CONTAINER_PATH`. The host directory already exists independently of the container and is mounted into the container's filesystem namespace. Database read/write operations directed at the mounted container path access the host-backed files.

A **volume** is a broader container-storage concept, but a *Podman named volume* is a different resource. The instructor labels Subtask 1.1 "Create Persistent Volume" yet `mkdir -p mysql-data` creates a plain host directory. This distinction matters in technical interviews and troubleshooting.

### Why the exact container path matters

MySQL stores its data at `/var/lib/mysql` in the course image. PostgreSQL 13 uses `/var/lib/postgresql/data` in the lab. Mounting to an unrelated path such as `/data` does not automatically move the database's real files there. A mount is only useful for persistence if the application writes to the mounted location.

### Why `$(pwd)` matters

A relative host folder isn't what gets passed. `$(pwd)` inserts your **current directory** into the mount argument. If your current directory changes between Task 1 and Task 2, `$(pwd)/mysql-data` refers to a *different* path and may create or target an empty data directory. This can look like data loss, but the old files may still exist in the old host folder.

## Without a persistent mount

If you omit `-v` entirely, MySQL/PostgreSQL still writes files during execution. The key question is **where those files are stored**. The image may declare an internal volume in its metadata, in which case the runtime may create an **anonymous volume**. Otherwise database writes may live in the container's writable layer.

Therefore avoid the blanket statement "without `-v`, data is always immediately destroyed." A more precise statement is:

- There is **no explicitly managed, stable host directory or named volume** that you deliberately reattach to the replacement container.
- Container-writable-layer changes are removed when that container is removed.
- An image-declared anonymous volume may survive some operations, but a new container does not automatically select the previous anonymous volume by name. Its retention also depends on how containers/volumes are removed.
- Relying on this behavior is a poor persistence strategy because recovery is non-obvious and easy to mishandle.

**Engineering answer to Knowledge Check #1:** Without an explicit persistent mount you cannot assume that a replacement container will reuse the original database files; intentionally attach a stable host directory or named volume and verify it.

## MySQL: initial setup and reinitialization

On **initial startup with an empty MySQL data directory**, the official MySQL entrypoint uses values such as:

```text
MYSQL_ROOT_PASSWORD=redhat123
MYSQL_DATABASE=testdb
MYSQL_USER=testuser
MYSQL_PASSWORD=user123
```

These are **initialization parameters**, not instructions to create new databases/users every time a container starts. The process starts the server, initializes its storage, and arranges initial credentials and the database.

On recreation in Task 2, the handout passes only `MYSQL_ROOT_PASSWORD`. Why does the original test user still work? Because the previously initialized data directory already contains the database metadata, accounts, permissions, and `lab_data` table. The image should detect existing database files and skip one-time initialization.

**Crucial risk:** Changing `MYSQL_ROOT_PASSWORD` in the environment after data has been initialized is not a real password-reset procedure. Database accounts reside in the database state; use the database's supported mechanisms to manage users and passwords.

### What the SQL statements actually accomplish

```sql
CREATE TABLE lab_data (id INT AUTO_INCREMENT PRIMARY KEY, message VARCHAR(255));
INSERT INTO lab_data (message) VALUES ('Persistent test data');
SELECT * FROM lab_data;
```

- `CREATE TABLE` writes schema metadata.
- `AUTO_INCREMENT PRIMARY KEY` generates a unique numeric row ID in the table.
- `VARCHAR(255)` holds the short message.
- `INSERT` writes a row into the database.
- `SELECT` queries stored records; seeing the exact message is the basic observable proof.
- `exit;` leaves the interactive MySQL client; it does not stop the database server container.

### Database readiness vs container running

`podman run -d` returning a container ID and `podman ps -a` showing `Up` do not mean MySQL accepts SQL connections immediately. First-time database initialization may be slower, especially on a small VM. Check `podman logs mysql-db` and connection readiness before retrying SQL. Avoid re-running the `CREATE TABLE` statement blindly after success because you'll get "table already exists."

## Why Task 2 proves persistence

Task 2 deliberately uses different container instances:

1. MySQL creates `testdb.lab_data` and inserts the row.
2. You stop and remove the **original container** (`podman stop`, then `podman rm`).
3. You start a **new container** with `-v .../mysql-data:/var/lib/mysql` pointing at the same host storage.
4. You run `SELECT * FROM lab_data;` from the new container.
5. If the old message is there, a replacement server has successfully read the persisted database files.

In a professional verification report, include the old/new container IDs or equivalent lifecycle evidence. Reusing `--name mysql-db` doesn't make it the same container; names can be reused after the previous container is removed.

### What this *doesn't* prove

- Backups exist.
- Data survives the loss of the physical host/storage device.
- Every transaction is durable under sudden power loss.
- Replication, high availability, or point-in-time recovery are configured.
- An upgrade to a different major version will read the files correctly.
- The process can restart automatically after a host reboot.

Those need distinct architecture and tests.

## PostgreSQL: same goal, different engine

The instructor's Task 3 is optional, but exercises the same engineering principle with PostgreSQL 13.

- Correct the invalid `mkdir -p-data` handout command to `mkdir -p pg-data`.
- Start `postgres:13` with `POSTGRES_PASSWORD`, `POSTGRES_USER`, and `POSTGRES_DB`.
- Bind mount `pg-data` to `/var/lib/postgresql/data` (plus `:Z` on suitable SELinux-enabled RHEL configurations).
- Create a `lab_data` table with a PostgreSQL `SERIAL PRIMARY KEY` and `TEXT` message column.
- Insert `'Postgres persistent data'`, then query it.
- Stop/remove and recreate the PostgreSQL container with **the same host directory and database version**.
- Query the record again.

The handout supplies only the initial SQL creation; the accompanying [README](README.md) provides the missing explicit remove/recreate/query commands needed to turn the optional challenge into an actual persistence verification.

### Why the database engine/version matters

Database storage is not a generic flat text folder. It contains engine-specific and version-specific structures, catalogs, logs, permissions, and transaction state. You cannot mount MySQL's directory into PostgreSQL and expect it to understand the files. Similarly, a casual major-version change may require a supported upgrade/migration method. Keep versions consistent for this lab.

PostgreSQL 13 and MySQL 8.0 were selected by the instructor; prefer currently supported versions for new non-lab deployments and plan migrations deliberately.

## Named volumes vs bind mounts

**The course uses bind mounts in both database tasks.** The following is separate exploration, *not an additional required Lab 11 step*.

| Concern | Bind mount (used in Lab 11) | Named volume (extra exercise) |
| --- | --- | --- |
| Create | `mkdir -p mysql-data` | `podman volume create mysql_state` |
| Host storage selected by | Absolute path such as `~/stateful-lab/mysql-data` | Runtime-managed volume name `mysql_state` |
| Attach | `-v "$(pwd)/mysql-data:/var/lib/mysql:Z"` | `-v mysql_state:/var/lib/mysql` |
| Placement | The chosen host folder | Podman's volume storage path |
| Ownership / SELinux | Host ownership and labels matter; `:Z` often useful on RHEL | Runtime typically manages the volume; still subject to permissions/security policy |
| Remove container | Host directory remains | Named volume normally remains |
| Deleting storage | Separate deletion of host path | Deliberate volume removal / pruning |

A rootless Podman managed-volume mount point may be inside the user's container storage directory rather than `/var/lib/containers/storage/...`, which is commonly associated with rootful use. Never hardcode a volume's storage path when `podman volume inspect` can tell you.

## SELinux and filesystem ownership

Three separate layers can affect database access:

1. **Linux filesystem ownership and mode:** The process must be able to create and update data files.
2. **Podman user namespaces/rootless UID mapping:** A user ID inside a container is not automatically the same host UID.
3. **SELinux mandatory access control (on enforcing systems):** Correct Unix ownership alone does not bypass an incompatible SELinux label.

### `:Z` vs `:z`

- `:Z`: Relabels the bind mount for private use by an appropriate container security context. In this lab the mount belongs to one database container at a time.
- `:z`: Requests a label suitable for sharing among multiple containers in applicable SELinux setups.
- Relabeling changes host directory labels; **avoid casually relabeling sensitive or broad host trees** (e.g. your whole home directory or system locations).

### Why blindly running `sudo chown -R 1001:1001` is risky

This line appears in the instructor's troubleshooting section; it is **not a required step**. It assumes the required host UID/GID is `1001:1001`, which isn't guaranteed for either official database image or a rootless user namespace. In the wrong directory it can corrupt ownership or make data inaccessible. Diagnosing with `podman logs`, inspecting permissions, and checking mapped container UIDs is better than arbitrary global ownership changes. `podman unshare` is useful for inspecting host files in the rootless storage user namespace.

**Interview point:** Unix permissions, SELinux labeling, and user namespace mappings solve *different* access-control problems.

## Security controls

**Answer to Knowledge Check #3 — What security considerations apply to host-stored database files?**

- **Secrets:** Never keep production passwords in public READMEs, shell history, environment examples, screenshots, or image layers. The course passwords are purposely disposable demonstration values. Use an appropriate secret manager or Podman secrets for real deployments.
- **Network exposure:** The instructor's `-p 3306:3306` / `-p 5432:5432` commonly publish beyond localhost. For a local VM lab, `-p 127.0.0.1:3306:3306` and `-p 127.0.0.1:5432:5432` reduce unnecessary exposure. Secure firewalls and authentication remain important.
- **Least privilege:** Use an application database user for routine queries, not the root/superuser account.
- **Filesystem ACLs:** Restrict host database directory access; don't grant broad world-write permissions.
- **SELinux/rootless security:** Use minimal permissions and scoped directory labeling, not blanket `chmod 777` or unsafe recursive ownership changes.
- **Sensitive records:** Database files and backups can contain user data; apply encryption at rest where required, controlled access, retention, and secure deletion policies.
- **Lifecycle and versions:** Patch images, maintain compatible engine versions, and design a safe backup/restore process.
- **Production boundaries:** A single-node lab database is not a production HA service.

## Migration and backups

**Answer to Knowledge Check #2 — How do you move persistent database data to another host?**

Copying live database files with a generic file copy may produce an **inconsistent** or unusable dataset while the server writes. Migration requires a database-aware plan.

### Option A — Logical backup/restore (often portable)

1. Produce a consistent dump with MySQL `mysqldump` (or equivalent) or PostgreSQL `pg_dump`, according to size and consistency requirements.
2. Securely transfer the dump to the target host.
3. Set up the destination with compatible software/configuration and restricted access.
4. Restore using the matching database client/tools.
5. Verify the schemas, row counts, representative queries, permissions, and application connectivity.
6. For production, plan write-freeze, synchronization, or replication/cutover to avoid missing writes during migration.

For illustration, using the course test database inside the local demo container:

```bash
# MySQL: writes a logical dump on your host; lab credentials only
podman exec mysql-db mysqldump -u root -predhat123 --databases testdb > testdb-mysql.sql

# PostgreSQL: writes a logical dump on your host; run only if Task 3 exists
podman exec postgres-db pg_dump -U testuser -d testdb > testdb-postgres.sql
```

These are **optional commands**, not original instructor tasks and not guaranteed to form a complete production backup strategy. Use suitable consistency settings, privileges, encryption, compression, and secure destinations. Avoid uploading database dumps to public GitHub.

### Option B — Physical backup / storage transfer

A storage snapshot or cold-copy of the underlying database files can be appropriate **if** the engine and storage procedure guarantee consistency. Usually coordinate with database-native backup tooling and version requirements. Copying a mounted directory while writes are ongoing is not automatically safe.

### Persistence ≠ backup ≠ high availability

- **Persistence:** data remains available to a new container using the same durable storage.
- **Backup:** a separate recoverable copy of data, ideally off the original failure domain and restore-tested.
- **High availability:** architecture designed to continue service through failures (replication, failover, redundancy, etc.).
- **Disaster recovery:** ability to restore systems/data after larger failures within defined recovery goals.

A successful Task 2 `SELECT` demonstrates persistence, not the other three.

## Failure scenarios and troubleshooting

### Scenario 1 — Recreated DB comes up empty

**Think:** Did we change `$(pwd)`? Did we accidentally point at a new directory? Does the source mount actually contain the expected database files? Did initialization run against empty storage? The fix is generally to **find the original directory**, not keep initializing replacements.

### Scenario 2 — Permission denied after adding the mount

**Think:** Is SELinux enforcing? Does the bind mount have an appropriate `:Z` label? Are the UID/GID mappings compatible? Did an earlier `sudo` operation alter ownership? Check logs and scoped permissions first; don't disable SELinux or globally relax permissions to "make it work."

### Scenario 3 — Container running, query fails

**Think:** Startup and application readiness are different states. Inspect logs; wait for proper readiness. Also check stored credentials and SQL database naming. Initial environment variables won't reset an initialized database user.

### Scenario 4 — Unexpectedly missing rows after power failure

**Think:** Crash recovery, filesystem durability, engine settings, write acknowledgements, and backup/recovery procedures. A graceful `podman stop` does not simulate abrupt power loss. Task 2 does not exercise crash consistency.

### Scenario 5 — Port conflict or unwanted remote access

**Think:** Who listens on 3306/5432? Run `ss -tulnp | grep 3306`; bind host services to `127.0.0.1` for local testing and use appropriate access controls. A VM's exposure also depends on its network settings.

### Scenario 6 — Same data directory, different major database image version

**Think:** Storage compatibility. Use supported engine-specific upgrade or dump/restore procedures; do not assume a later major version can open any previous files in place.

### Scenario 7 — The host or disk is destroyed

**Think:** A bind mount on that same host cannot survive loss of the host's storage. You need backups or replicated storage and a recovery plan.

## Real-world architecture and interview questions

### A realistic small production topology

```text
                Application / API service
                            │
                    Private networking
                            │
                     Database service
                            │
              Durable database storage
                            │
         Separate, restorable backup system
```

The lab demonstrates only the database + host bind mount part. It does not create an application tier, scheduler-managed volume, backup system, automatic restart policy, replication, or remote storage.

In Kubernetes/OpenShift, a containerized database often uses **PersistentVolumes (PV)**, **PersistentVolumeClaims (PVC)**, a suitable **StorageClass**, and workload controllers such as **StatefulSets**. PV/PVC is not the same resource as a Podman volume, although both support separating workload lifecycle from storage. A StatefulSet does not eliminate the need for backups and operational planning.

### Interview Q&A

**Q1. Why is a database container stateful?**  
Because it must retain its data/schema/transaction state across executions. Recreating compute must not silently discard business records.

**Q2. Does `podman stop` delete data?**  
No. Stopping alone ordinarily leaves the container and any associated storage. `podman rm` removes the container, but host bind-mount data remains unless explicitly deleted.

**Q3. Is a bind mount the same as a named volume?**  
No. A bind mount points to a chosen host path; a named volume is managed and referenced by the runtime by name.

**Q4. Why did MySQL work after recreating without `MYSQL_USER`?**  
The initialized database state and user persisted on the same mounted directory. These env variables primarily govern initial setup.

**Q5. Can you copy `/var/lib/mysql` into a PostgreSQL volume?**  
No. MySQL and PostgreSQL storage formats are incompatible; migrate logically with suitable tools and schema conversion where needed.

**Q6. What is the practical purpose of `:Z`?**  
It requests private SELinux relabeling for a bind mount in compatible Podman setups; it is not a generic Unix permissions fix.

**Q7. Why is `sudo chown -R 1001:1001` potentially wrong?**  
UIDs differ across images, runtimes, and user namespaces. Determine the actual process and mapped file ownership before changing permissions.

**Q8. Does a passing persistence test mean zero data-loss risk?**  
No. A container lifecycle test doesn't simulate host failure, simultaneous writes, accidental deletion, media corruption, or bad backups.

**Q9. How do you distinguish a healthy container from a ready database?**  
Use DB-aware health/readiness checks or successful connection/query tests, not just `podman ps`.

**Q10. Which evidence would you attach to a GitHub lab?**  
The original data query, proof that the original container was removed and a new instance started, and the same query returning the original row afterward, with sensitive data hidden.

## What's actually proven

| Claim | Status and source of confidence |
| --- | --- |
| MySQL storage and recovery were practiced | **Learner-reported:** Tasks 1–2 completed. No attached execution logs. |
| PostgreSQL commands and recovery procedure documented | **Yes:** reproducible instructions included in the README. |
| PostgreSQL persistence test succeeded on learner's system | **Not yet explicitly confirmed.** |
| Actual MySQL/PostgreSQL SQL outputs attached here | **No.** Code blocks marked as examples, not retained logs. |
| Host-loss resilience, backups, HA, production safety proven | **No.** These are separate engineering concerns. |

### Engineering takeaway

> **A replaceable container is not the same as a recoverable database.** Persisted storage is only the beginning; operational confidence also requires database-aware validation, access controls, backups, and tested restores.

**Return to:** [Practical README](README.md) · [All Red Hat 1 labs](../LABS-INDEX.md)
