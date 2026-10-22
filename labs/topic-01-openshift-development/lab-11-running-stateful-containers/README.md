# Lab 11 — Running Stateful Containers

> **Learning track:** Domain 5 → Linux and Open Source → Red Hat 1  
> **Technology:** Podman, MySQL 8.0, PostgreSQL 13, Linux bind mounts  
> **Execution status (learner-reported):** Tasks 1 and 2 completed. Task 3 is an **optional challenge**; its successful execution has **not yet been explicitly confirmed**.  
> **Evidence status:** This repository contains reproduction steps and *expected* outputs—not a captured terminal transcript, automatic test result, or independent confirmation.  
> **Companion:** [DEEP-DIVE.md](DEEP-DIVE.md) — technical internals, risk analysis, production distinctions, and interview prep.

## Why this lab matters

A database container is replaceable; the database's state should not disappear when that container is removed. Here we create records in MySQL, remove and recreate the container, then query the same data. The optional PostgreSQL task repeats that pattern with a different database engine.

**Completion criteria:** Recovering an existing row from a freshly recreated container while reusing the **same host storage directory**. The directory surviving is not, by itself, proof that the database can read the records.

## Objectives

- Understand and implement persistent storage for stateful containers.
- Run MySQL and (optionally) PostgreSQL containers with volume mounts.
- Verify database records across container removal and recreation.

## Prerequisites

- Podman or Docker installed; commands here use **Podman** (preferred for OpenShift-oriented learning).
- Basic Linux command-line skills.
- At least **2 GB free disk space** for the exercises and container images.
- Internet access to pull the MySQL/PostgreSQL images.
- Linux host or WSL2; on RHEL with SELinux enabled, prefer appropriately labeled bind mounts.
- Free local ports **3306** and **5432**, or change host-side bindings.

**Important lab security note:** `redhat123` and `user123` are the instructor's **demonstration passwords**, published here only for reproducing this lab. Never reuse them for real workloads. A password passed via `-e` or the `-pPASSWORD` MySQL option may appear in shell history, process arguments, or container metadata. Do **not** expose demo database ports to a public network.

---

## Lab setup — both original commands

**1. Verify Podman:**

```bash
podman --version
```

**Expected:** a version string such as `podman version 4.0.0`. Your actual version may differ.

**2. Create the working directory and enter it:**

```bash
mkdir -p ~/stateful-lab && cd ~/stateful-lab
```

Every subsequent `$(pwd)` below is expected to resolve to the **same** `~/stateful-lab` directory. Recheck with `pwd` before recreating a container. Switching working directories and inadvertently mounting a fresh empty directory is a common way to misdiagnose "lost data."

---

## Task 1 — Running a MySQL container with persistent storage

### Subtask 1.1 — Create the host storage directory

**Instructor command:**

```bash
mkdir -p mysql-data
```

This creates `~/stateful-lab/mysql-data`. It is a **bind-mount source directory**, not a Podman-managed *named volume*. Although the task heading calls it a "Persistent Volume," the actual command creates a normal directory on the host.

### Subtask 1.2 — Launch MySQL 8.0

**Instructor command (preserved without modifications):**

```bash
podman run -d \
  --name mysql-db \
  -e MYSQL_ROOT_PASSWORD=redhat123 \
  -e MYSQL_DATABASE=testdb \
  -e MYSQL_USER=testuser \
  -e MYSQL_PASSWORD=user123 \
  -v $(pwd)/mysql-data:/var/lib/mysql \
  -p 3306:3306 \
  docker.io/library/mysql:8.0
```

**Alternative for an SELinux-enabled RHEL learning VM:** If the original command fails due to SELinux denials, use this **instead of**, not in addition to, the original `podman run`. Binding the port to `127.0.0.1` also reduces accidental exposure:

```bash
podman run -d \
  --name mysql-db \
  -e MYSQL_ROOT_PASSWORD=redhat123 \
  -e MYSQL_DATABASE=testdb \
  -e MYSQL_USER=testuser \
  -e MYSQL_PASSWORD=user123 \
  -v "$(pwd)/mysql-data:/var/lib/mysql:Z" \
  -p 127.0.0.1:3306:3306 \
  docker.io/library/mysql:8.0
```

| Argument | Meaning |
| --- | --- |
| `-d` | Detached container; this does **not** guarantee the database is healthy. |
| `--name mysql-db` | Container name reused after the old container has been removed. |
| `MYSQL_ROOT_PASSWORD` | Initial root password when the data directory is empty. |
| `MYSQL_DATABASE=testdb` | Database initialized on the first run. |
| `MYSQL_USER=testuser` / `MYSQL_PASSWORD=user123` | Application user credentials initialized on the first run. |
| `-v $(pwd)/mysql-data:/var/lib/mysql` | Host bind mount → MySQL data directory. |
| `-p 3306:3306` | Publishes MySQL port; without a host address, this can listen on all host interfaces. |
| `:Z` (RHEL alternative) | Applies a **private SELinux relabel** to the source mount; it may modify host file labels. |
| `docker.io/library/mysql:8.0` | Course's official MySQL image reference. |

**Original verification command:**

```bash
podman ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}"
```

**Expected observation:** `mysql-db` appears with a running status after successful startup. The returned container ID, runtime status, and startup delay depend on your machine. Check actual readiness instead of assuming `Running` means queries will work:

```bash
podman logs mysql-db
podman exec mysql-db mysqladmin ping -h 127.0.0.1 -uroot -predhat123
```

The `mysqladmin` command is an **additional diagnostic**, not an instructor-required task. If the MySQL image, authentication, or startup is still settling, inspect logs and retry after it reports ready for connections. Avoid storing lab passwords in reusable scripts.

### Subtask 1.3 — Connect and insert data

**Instructor connection command:**

```bash
podman exec -it mysql-db mysql -u testuser -puser123 testdb
```

Then type the **original SQL statements** into the MySQL client:

```sql
CREATE TABLE lab_data (id INT AUTO_INCREMENT PRIMARY KEY, message VARCHAR(255));
INSERT INTO lab_data (message) VALUES ('Persistent test data');
SELECT * FROM lab_data;
exit;
```

**Expected query content (illustration only):**

```text
+----+----------------------+
| id | message              |
+----+----------------------+
|  1 | Persistent test data |
+----+----------------------+
```

`CREATE TABLE` makes the schema, `INSERT` writes a row, and `SELECT` checks the stored value. `exit;` exits the MySQL client, not the MySQL container. Exact formatting and row numbers may differ if you rerun the inserts.

**Practical evidence to capture:** your actual `SELECT` result before container removal, alongside the container name or ID. Do not publish exposed credentials or confidential host information.

---

## Task 2 — Verify that MySQL data survives container replacement

### Subtask 2.1 — Stop and remove the old container

**Both instructor commands:**

```bash
podman stop mysql-db
podman rm mysql-db
```

`podman stop` requests shutdown of the database process. `podman rm` removes that container's writable layer and metadata, **not** the separate host directory `mysql-data` used as a bind mount. Stop gracefully before removal where possible.

### Subtask 2.2 — Recreate MySQL using the same stored data

**Instructor command (preserved):**

```bash
podman run -d \
  --name mysql-db \
  -e MYSQL_ROOT_PASSWORD=redhat123 \
  -v $(pwd)/mysql-data:/var/lib/mysql \
  -p 3306:3306 \
  docker.io/library/mysql:8.0
```

**RHEL/SELinux alternative (choose one):**

```bash
podman run -d \
  --name mysql-db \
  -e MYSQL_ROOT_PASSWORD=redhat123 \
  -v "$(pwd)/mysql-data:/var/lib/mysql:Z" \
  -p 127.0.0.1:3306:3306 \
  docker.io/library/mysql:8.0
```

**Why are `MYSQL_DATABASE`, `MYSQL_USER`, and `MYSQL_PASSWORD` omitted this time?** Because MySQL should detect **already initialized database files** inside `/var/lib/mysql`. The existing `testdb`, `testuser`, permissions, and table live in those persisted database files; the initialization variables are not reapplied to existing data. Changing initialization variables does not reliably change existing database passwords/users.

Make sure you still are in `~/stateful-lab`; otherwise `$(pwd)/mysql-data` could point at a different directory. The recreated container is a new container even though it has the same name.

### Subtask 2.3 — Query the previously saved record

**Instructor verification command:**

```bash
podman exec -it mysql-db mysql -u testuser -puser123 testdb -e "SELECT * FROM lab_data;"
```

**Expected:** the row with `Persistent test data` created in Task 1 is present. This is the core persistence verification. If it fails, check the database logs, actual storage path, readiness, and user credentials; do not immediately reset/delete the data directory.

**Proof-of-work comparison:** record the original `SELECT` result and the `SELECT` result after container recreation. Ideally retain the old and new container IDs from `podman ps -a` to show it really was replaced.

---

## Task 3 — PostgreSQL 13 implementation (**optional challenge**)

> This entire section is documented, but successful execution of Task 3 has **not been confirmed** by the learner. Do not list it as an observed success until you actually complete and verify the recovery test.

### Subtask 3.1 — Create a PostgreSQL host directory

The instructor handout contains this **typo (DO NOT run this line):**

```bash
mkdir -p-data
```

**Corrected executable command:**

```bash
cd ~/stateful-lab
mkdir -p pg-data
```

Creates the directory that will become PostgreSQL's data storage. This is another **bind mount**, not a Podman-managed named volume.

### Subtask 3.2 — Launch the PostgreSQL container

**Instructor command (preserved):**

```bash
podman run -d \
  --name postgres-db \
  -e POSTGRES_PASSWORD=redhat123 \
  -e POSTGRES_USER=testuser \
  -e POSTGRES_DB=testdb \
  -v $(pwd)/pg-data:/var/lib/postgresql/data \
  -p 5432:5432 \
  docker.io/library/postgres:13
```

**SELinux-enabled RHEL/localhost alternative (choose one, not both):**

```bash
podman run -d \
  --name postgres-db \
  -e POSTGRES_PASSWORD=redhat123 \
  -e POSTGRES_USER=testuser \
  -e POSTGRES_DB=testdb \
  -v "$(pwd)/pg-data:/var/lib/postgresql/data:Z" \
  -p 127.0.0.1:5432:5432 \
  docker.io/library/postgres:13
```

`POSTGRES_*` settings create the database/user only when the database storage is first initialized. PostgreSQL 13's data directory is `/var/lib/postgresql/data` for this image and handout.

**Extra readiness check:**

```bash
podman ps -a
podman exec postgres-db pg_isready -U testuser -d testdb
```

Expected readiness wording resembles `accepting connections`. Actual address and formatting may vary.

### Subtask 3.3 — Create PostgreSQL test data

**Exact instructor SQL command:**

```bash
podman exec -it postgres-db psql -U testuser -d testdb -c "CREATE TABLE lab_data (id SERIAL PRIMARY KEY, message TEXT); INSERT INTO lab_data (message) VALUES ('Postgres persistent data');"
```

**Recommended additional verification of the inserted record:**

```bash
podman exec postgres-db psql -U testuser -d testdb -c "SELECT * FROM lab_data;"
```

**Expected query content:**

```text
 id |          message
----+-------------------------
  1 | Postgres persistent data
(1 row)
```

**Follow the handout's instruction to repeat MySQL's remove/recreate/recovery method:**

**A. Stop and remove the PostgreSQL container:**

```bash
podman stop postgres-db
podman rm postgres-db
```

**B. Recreate it with the SAME `pg-data` directory (RHEL alternative shown):**

```bash
cd ~/stateful-lab
podman run -d \
  --name postgres-db \
  -e POSTGRES_PASSWORD=redhat123 \
  -e POSTGRES_USER=testuser \
  -e POSTGRES_DB=testdb \
  -v "$(pwd)/pg-data:/var/lib/postgresql/data:Z" \
  -p 127.0.0.1:5432:5432 \
  docker.io/library/postgres:13
```

If you initially used the **unmodified instructor version**, keep its matching `-v $(pwd)/pg-data:/var/lib/postgresql/data` and `-p 5432:5432` options on recreation instead. **Do not** run both container-creation variants concurrently.

**C. Confirm the database is ready and recover the original row:**

```bash
podman exec postgres-db pg_isready -U testuser -d testdb
podman exec postgres-db psql -U testuser -d testdb -c "SELECT * FROM lab_data;"
```

**Expected:** `Postgres persistent data` is returned from the recreated container. A newly initialized, empty database with the same name does **not** count as successful recovery.

---

## Original troubleshooting commands — all retained

### 1. File permission errors

The instructor suggests:

```bash
sudo chown -R 1001:1001 mysql-data/
```

**Caution:** This is **not a universally safe fix**. UID `1001` is not guaranteed to match the MySQL process identity, particularly for rootless Podman and user namespaces. Incorrectly changing ownership can damage access or complicate recovery. **Do not run blindly.** Instead first inspect the exact permission error and environment:

```bash
podman logs mysql-db
ls -ld mysql-data pg-data
podman unshare ls -ld mysql-data
```

For SELinux denials, the alternative mounts with `:Z` may be appropriate. Ownership and SELinux labels solve different problems. `:z` is for suitable shared-volume SELinux labeling scenarios; don't interchange it with `:Z` casually.

### 2. Port conflicts

**Instructor command:**

```bash
ss -tulnp | grep 3306
```

This checks for a listener on port 3306. If another service already has it, stop the conflicting test service or choose a different **host port** (e.g., `127.0.0.1:3307:3306`). PostgreSQL uses 5432; apply the same idea there.

### 3. Container logs

**Instructor command:**

```bash
podman logs mysql-db
```

Use `podman logs postgres-db` for PostgreSQL (additional). Common causes include bad permissions, initial image download failures, insufficient disk space, incorrect working directory, or trying to connect before startup completes.

### 4. Additional real-world troubleshooting

| Symptom | Likely cause | First check |
| --- | --- | --- |
| Container `Exited` immediately | DB initialization/permission/port problem | `podman ps -a`; `podman logs mysql-db` |
| `Can't connect` | Database not ready or container stopped | Logs and readiness check |
| SQL `table already exists` | Task rerun against the same initialized volume | `SELECT` first; do not overwrite data blindly |
| `Access denied` / authentication error | Wrong stored DB credentials or username | Verify originally initialized user/password; initial env vars aren't password-reset commands |
| `permission denied` on directory | SELinux context or Unix ownership mapping | Inspect actual logs and labels; consider `:Z` |
| `address already in use` | Port 3306/5432 occupied | `ss -tulnp` |
| Recreated container has empty DB | Different `$(pwd)` directory/mount or unintentionally new data directory | `pwd`, mount arguments, existing host data |
| Image tag/version mismatch | Incompatible data directory format or changed engine version | Use matching MySQL 8.0 or PostgreSQL 13 tags for this lab |

---

## Conclusion — correctly scoped

**Learner-reported completed:** MySQL container initialized; a table and row were created; container was stopped and removed; a new container using the **same** host mount recovered the row (Tasks 1–2).  
**Optional Task 3:** Complete instructions and verification criteria for PostgreSQL are provided above; its actual completion **awaits learner confirmation**.  
**General lesson:** Stateful services need persistent storage separate from the lifecycle of their compute containers; persistence alone is not a backup or high-availability solution.

## Knowledge check — all instructor questions

1. **What happens if you omit `-v`?** See [Deep Dive — Without a mount](DEEP-DIVE.md#without-a-persistent-mount).
2. **How would you migrate this persistent data to another host?** See [Deep Dive — Migration and backups](DEEP-DIVE.md#migration-and-backups).
3. **What security considerations apply to host-stored database files?** See [Deep Dive — Security controls](DEEP-DIVE.md#security-controls).

## Further exploration — all instructor suggestions

1. **Experiment with named volumes:** `podman volume create` and mount one to the correct database directory. See [Deep Dive — Named vs bind mounts](DEEP-DIVE.md#named-volumes-vs-bind-mounts).
2. **Try multi-container setups:** attach a separate application container and database container to a controlled private network; don't expose database ports to the internet.
3. **Explore backup strategies:** database-consistent dumps, restore drills, retention, and host-loss scenarios.

### Optional cleanup — not part of the instructor's required tasks

**Only after saving real evidence and deciding you do not need these demo containers:**

```bash
podman stop mysql-db postgres-db
podman rm mysql-db postgres-db
```

**Do not delete** `~/stateful-lab/mysql-data` or `~/stateful-lab/pg-data` if you still need the test databases. Stopping/removing containers and deleting host data are entirely different actions. The optional cleanup may error if you never ran Task 3; remove only containers that actually exist.

## GitHub proof-of-work checklist

- [x] Tasks 1 and 2 — learner-reported completed (MySQL persistent row recovery).
- [ ] Task 3 — optional PostgreSQL completion not explicitly confirmed.
- [ ] Add actual before/after SQL screenshots or sanitized logs if available.
- [ ] Verify links and metadata in the repository lab index.
- [ ] Never present example output as a real execution transcript.

**Recommended evidence:** (1) MySQL row before deletion, (2) MySQL row after container recreation, (3) optional PostgreSQL before/after. Screenshots should hide sensitive information.

**No custom Dockerfile or Containerfile is required.** This lab runs existing MySQL/PostgreSQL images; its essential engineering artifacts are the commands, database verification, troubleshooting, and explanation.

**Next:** [Engineering Deep Dive](DEEP-DIVE.md) · [All labs](../LABS-INDEX.md) · [Engineering Proof of Work](../../evidence/PROOF-OF-WORK.md)
