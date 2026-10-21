# Lab 12 — Engineering Deep Dive: Container Database Backup & Restore

**Track:** Domain 5 → Linux and Open Source → Red Hat 1  
**Companion:** [Practical README.md](README.md)  
**Completion:** All tasks completed, **learner self-reported**; examples below are explanations and reproducibility references, not independently captured execution logs.

## 1. The real engineering problem

Lab 10 asked: *Can a file survive container deletion?* Lab 11 asked: *Can a database use persistent storage across container recreation?* Lab 12 asks something different:

> **If the running database or its underlying storage is damaged, can we reconstruct the required database state from an independent backup?**

Persistent storage preserves data across the container lifecycle. It does not independently protect against deleting the volume, corruption, ransomware, an incorrect SQL statement, host storage failure, or a failed migration. Backups capture data at a particular point so it can be re-created or restored elsewhere.

### Mental model

```text
                  SOURCE (MySQL 8.0 container)
                   database: testdb
               table: employees (two rows)
                           |
                           | mysqldump (logical SQL export)
                           v
           Host: ~/backup-lab/testdb_dump.sql
                           |
                           | copy into a helper container's mount
                           v
                 Podman volume: backup-vol
                 /backup/mysql/testdb_dump.sql
                           |
                           | read file back out of the volume
                           v
              Host: testdb_dump_from_volume.sql
                           |
                           | mysql client receives SQL on STDIN
                           v
                NEW MySQL container: mysql-restore
                           |
                           v
               SELECT * FROM testdb.employees;
                  John Doe   |   Jane Smith
```

The backup volume and the database's own storage are **different things**. In Lab 12 the source MySQL container is not configured with a host-mounted database directory; the exported SQL file is the portable recovery artifact.

## 2. Four different storage and lifecycle concepts

| Term | Meaning | Is it independently a backup? |
| --- | --- | --- |
| Container writable layer | Per-container filesystem changes; usually removed with the container | No |
| Bind mount | Container accesses a specific host directory | No |
| Named volume | Podman-managed persistent storage | No |
| SQL logical dump | Database contents/schema serialized as SQL | **Can serve as a backup**, if complete, consistent, protected and actually restorable |

**Why this matters:** A volume can keep corrupted data just as persistently as healthy data. A good backup strategy includes recovery testing, data integrity checks and retention beyond the original host.

## 3. How database initialization works

Instructor source container:

```bash
podman run -d --name mysql-db \
  -e MYSQL_ROOT_PASSWORD=redhat \
  -e MYSQL_DATABASE=testdb \
  -e MYSQL_USER=testuser \
  -e MYSQL_PASSWORD=testpass \
  docker.io/library/mysql:8.0
```

- `podman run` creates the container and starts the image's configured program.
- `-d` returns control to your shell and doesn't guarantee database readiness.
- `-e` sets environment variables for the container process.
- The official MySQL image can use these environment variables **when initializing a new empty database directory**. Reusing already-initialized MySQL data generally does not recreate users/databases based on changed environment variables.
- Pulling `mysql:8.0` retrieves an image from Docker Hub when not already cached; version behavior can vary across minor patch revisions within the tag.

The shell command `podman ps -f name=mysql-db` tests container status, whereas a MySQL client connection or a successful `mysqladmin ping` establishes a better readiness signal. `mysqladmin ping` alone should not be treated as authentication validation in every circumstance; use an actual query for final verification.

## 4. Why SQL rows are useful backup test data

```sql
USE testdb;
CREATE TABLE employees (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(50));
INSERT INTO employees (name) VALUES ('John Doe'), ('Jane Smith');
SELECT * FROM employees;
```

- `id INT AUTO_INCREMENT PRIMARY KEY` provides a numeric auto-assigned identifier.
- `VARCHAR(50)` stores strings with a maximum of 50 characters.
- `INSERT` creates two recognizable records, making the restore observable.
- `SELECT` provides a before-restore baseline.

A stronger production test would also validate constraints, indexes, counts, character encodings, transactions, relationships and application behavior. Two sample records prove only the limited lab scenario—not full disaster recovery readiness.

## 5. Unpacking the mysqldump command

```bash
podman exec mysql-db /usr/bin/mysqldump -u root -predhat testdb > testdb_dump.sql
```

**Process boundary:** `podman exec` launches `mysqldump` **inside** the running container. MySQL's database server supplies schema/data; `mysqldump` emits SQL text to standard output.

**Shell boundary:** The `>` operator is parsed by the **host shell**. It creates/truncates `testdb_dump.sql` under your current host directory before redirecting the command's stdout. The SQL file is not automatically written inside the source container.

**Subtle failure:** If the command fails, shell redirection may still have created an empty file. `ls -l` by itself proves existence, not successful backup. Pair size/content checks with a real import into an independent database:

```bash
ls -l testdb_dump.sql
head -n 5 testdb_dump.sql
test -s testdb_dump.sql && echo "Nonempty dump"
```

`head` typically shows SQL comments/header; it doesn't confirm employee records. A successful restore and SELECT are the meaningful validation.

### Consistency and production considerations

For transactional InnoDB tables, a common starting point is a transactionally consistent logical dump:

```bash
podman exec mysql-db mysqldump \
  --single-transaction --quick \
  -u root -predhat testdb > testdb_consistent.sql
```

This is **additional study material**, not the instructor's required command or a claim of tests performed. `--single-transaction` is most meaningful with transactional engines such as InnoDB; concurrent schema changes (DDL) or nontransactional tables may need extra controls. Capturing routines/events or a server-wide set of databases may require additional flags, privileges or dedicated backup tools. Large production databases may need physical/streaming backups and binlogs to meet recovery objectives.

## 6. Persistent named-volume copy — why the helper container exists

```bash
podman volume create backup-vol
podman run -it --rm -v backup-vol:/backup alpine sh
```

The first command creates Podman-managed storage. The second starts a short-lived Alpine helper and attaches that storage at `/backup`.

Inside it:

```sh
mkdir -p /backup/mysql
exit
```

The helper container disappears because of `--rm`, while the named volume remains. Thus the subdirectory `/backup/mysql` survives.

The lab's nested command:

```bash
podman cp testdb_dump.sql $(podman create --name temp -v backup-vol:/backup alpine):/backup/mysql/
podman rm temp
```

The shell first runs the nested `podman create`, substitutes its returned container ID into `podman cp`, and then copies the host file into the container path. The path is intended to refer to the mounted volume. This is technically compact but fragile when troubleshooting; split it into explicit commands or stream the file into a helper that mounts the volume if needed.

### Safer-to-debug streaming copy

```bash
podman run --rm -i -v backup-vol:/backup docker.io/library/alpine \
  sh -c 'mkdir -p /backup/mysql && cat > /backup/mysql/testdb_dump.sql' \
  < testdb_dump.sql
```

Here `< testdb_dump.sql` is read on the host. `-i` keeps STDIN open, and the helper's `cat` writes to the volume. No temporary container with an unpredictable ID is left behind. You can inspect the volume with:

```bash
podman run --rm -v backup-vol:/backup alpine ls -l /backup/mysql
```

**Failure boundary:** Both the original host copy and the named-volume copy can still reside on the **same physical machine**. A host disk failure could eliminate both. Treat copying into `backup-vol` as a lab exercise, not off-site protection.

## 7. Root cause of Task 3.2's instructor bug

Original Task 3.2:

```bash
podman run --rm -v backup-vol:/backup alpine cp /backup/mysql/testdb_dump.sql /tmp/
podman cp $(podman create --name temp -v backup-vol:/backup alpine):/tmp/testdb_dump.sql .
podman rm temp
```

**Trace the data:**

1. An Alpine helper starts. Its volume is mounted at `/backup`.
2. `cp` writes the dump into **that container's own** `/tmp/` directory.
3. The container immediately exits and `--rm` deletes its writable layer; that `/tmp` is gone.
4. A **new** `temp` container is created. Its `/tmp` has no copied dump.
5. `podman cp ...:/tmp/testdb_dump.sql .` cannot recover the file from the first container.

**Fix the *data path*, not just the filename.** The original backup really resides at `/backup/mysql/testdb_dump.sql` on the named volume. Run a new container mounting that same volume and stream the file to a known host path:

```bash
podman run --rm -v backup-vol:/backup:ro docker.io/library/alpine \
  cat /backup/mysql/testdb_dump.sql > testdb_dump_from_volume.sql
```

- `:ro` mounts the backup volume read-only, reducing accidental modification during recovery.
- `cat` reads the actual stored SQL file from the persistent mount.
- `>` writes the recovered SQL content to a host file.

This creates a traceable chain: **MySQL → host dump → named volume → recovered host dump → new MySQL instance.**

## 8. Why the restore uses stdin (`-i`) and not a bind mount

```bash
podman exec -i mysql-restore mysql -u root -predhat testdb < testdb_dump_from_volume.sql
```

- `podman exec -i` keeps standard input attached to the MySQL client inside `mysql-restore`.
- `mysql -u root -predhat testdb` authenticates and selects the target database.
- Host-shell `<` streams the SQL file *into* MySQL via STDIN.
- `-t` is unnecessary here because this is not an interactive terminal session.

**Why a different database container matters:** If you only query the original source container, you haven't proven recovery from backup. The target `mysql-restore` represents a separate database instance initialized without the source's live data files.

**Why the instructor's original restore command is insufficient evidence of volume recovery:**

```bash
podman exec -i mysql-restore mysql -u root -predhat testdb < testdb_dump.sql
```

That can successfully import the original *host dump* directly. Unless you retrieved the dump through `backup-vol` first, it doesn't test that the backup stored in the volume is actually readable.

## 9. How to validate a restore like an engineer

Instructor verification:

```bash
podman exec -it mysql-restore mysql -u root -predhat -e "SELECT * FROM testdb.employees;"
```

**Expected, not claimed historical output:**

```text
+----+------------+
| id | name       |
+----+------------+
|  1 | John Doe   |
|  2 | Jane Smith |
+----+------------+
```

A basic evidence chain should establish:

1. Rows existed in the **source** database.
2. A nonempty SQL dump was produced.
3. The SQL file existed in the **named volume**.
4. It could be read back from the volume, preferably to a distinct output file.
5. A **new** MySQL instance could accept the SQL import.
6. The restored SQL query returned the same rows.

For a stronger independent test, record checksums/counts, verify schema and indexes, and rehearse restoration from the *off-host* backup location. Avoid claiming measurable recovery time without timing an actual restore.

## 10. RPO and RTO — real disaster recovery terms

**RPO (Recovery Point Objective):** How much recent data loss is acceptable, expressed as time. If backups run once per day, the worst-case data gap can approach a full day, depending on the incident and recovery design.

**RTO (Recovery Time Objective):** How quickly the system must be restored to an acceptable operational state after disruption.

Lab 12 demonstrates the procedure for **logical export and import**, but it does not measure RPO/RTO or guarantee zero data loss. Production recovery may also need binary logs, point-in-time recovery, managed backups, replication and runbooks tested under failure conditions.

## 11. Security and safety concerns

- **Credentials:** `-predhat` and `-e MYSQL_ROOT_PASSWORD=redhat` expose demonstration secrets in commands/environment and can show up in shell history, process lists or inspect data. Never copy these patterns into production unchanged; use managed secret solutions and least-privilege accounts.
- **SQL dump sensitivity:** Backups may contain customer data, credentials, access tokens or personal information. Restrict access, encrypt as appropriate, control retention and audit recovery access.
- **Rootless Podman:** UID/GID mapping can make host bind-mount ownership differ from container IDs. Do not run arbitrary `chown -R` to fix errors without checking mappings.
- **SELinux labels:** `:Z` privately relabels an SELinux-managed **bind mount** for use by a container. This is often not required for Podman-managed named volumes, and inappropriate labeling can interfere with sharing. Inspect actual errors before adding it.
- **Integrity:** A backup that exists but cannot be restored is not operationally useful. Validate the backup and test restores.
- **Retention:** The exact cleanup step `podman volume rm backup-vol` destroys the lab's volume copy. A real retention policy and independent off-host copies are essential.
- **Compatibility:** Restoring logical dumps into another database version may require compatibility checking; use consistent character sets, collations and compatible SQL definitions.

## 12. Troubleshooting decision tree

```text
MySQL container not running?
 ├── Check podman logs mysql-db
 ├── Check image pull, name collision, disk and initialization errors
 └── Wait for MySQL readiness

Dump missing / empty?
 ├── Check working directory (pwd)
 ├── Check mysqldump authentication / database name
 └── Re-export and verify nonempty content

Dump absent from backup-vol?
 ├── Confirm podman volume exists
 ├── Inspect the helper container's /backup/mysql directory
 └── Try the stdin-based streaming copy

Cannot recover file from /tmp?
 └── Instructor bug: ephemeral /tmp vanished; read /backup/mysql instead

Import fails?
 ├── Check mysql-restore readiness / credentials
 ├── Ensure host SQL file is nonempty
 ├── Check MySQL errors, compatibility, existing schema
 └── Use a fresh restore container for a clean rerun

SELECT returns no rows?
 ├── Confirm import used backup-vol-derived SQL
 ├── Confirm selected schema and table
 └── Inspect source dump contents and import diagnostics
```

## 13. Interview and review questions (with answers)

**Q1. Is a named volume the same as a backup?**  
No. A volume persists filesystem data independent of a container's lifecycle but usually remains coupled to a host/storage system. A backup is a recoverable, protected copy intended for restoration after loss or corruption.

**Q2. Why use `mysqldump` instead of copying `/var/lib/mysql` from a running container?**  
`mysqldump` performs a logical export through the DB engine. Arbitrary copies of live database files can be inconsistent; physical backups need engine-aware procedures, coordination or valid snapshots.

**Q3. Where is `testdb_dump.sql` created?**  
On the host's current directory, because `>` is interpreted by the host shell running `podman exec`.

**Q4. Does `podman rm mysql-db` automatically delete a named backup volume?**  
No, the separate named `backup-vol` survives ordinary container removal; deleting or pruning the volume itself can remove its contents.

**Q5. What is wrong with copying the dump to `/tmp` inside `podman run --rm` and starting another helper?**  
The first container's private `/tmp` is deleted with the container. A later new container will not contain that file unless `/tmp` itself was backed by shared storage, which the original command did not do.

**Q6. Why retrieve the SQL from `backup-vol` even though the original host dump already exists?**  
To verify the actual stored backup can be read, not just the source host copy.

**Q7. Why is `podman exec -i` used during the import?**  
It keeps STDIN available so the SQL redirected by the host's `<` operator reaches the MySQL client process inside the target container.

**Q8. Can this lab alone guarantee recovery from a disk failure?**  
No. Both the host SQL file and named volume can be lost together. Off-host copies, retention, encryption, integrity verification and tested restores are required for serious recovery plans.

**Q9. What do RPO and RTO measure?**  
RPO measures tolerable data-loss time; RTO measures tolerable recovery time.

**Q10. What would you change for production?**  
Use secured secrets, dedicated backup privileges, suitable consistent-backup settings, off-host encrypted storage, access controls, monitoring, retention, binlog/PITR as needed, and repeatable restore drills.

## 14. Final engineering takeaway

**A green container health check is not a backup. A present volume is not an independently verified restore.** The decisive step is rebuilding data in a separate database instance from a known, readable backup artifact.

This repository entry documents a **learner-completed exercise (self-reported)**; it intentionally avoids invented log timestamps, benchmark data, screenshots, or claims of enterprise production experience.

**Navigate:** [Practical lab](README.md) · [Red Hat 1 lab index](../LABS-INDEX.md) · [Proof-of-work policy](../../evidence/PROOF-OF-WORK.md)
