# Lab 12 — Backup and Restore Data

**Learning track:** Domain 5 → Linux and Open Source → Red Hat 1  
**Runtime:** Podman with MySQL 8.0 and Alpine  
**Completion:** **Completed — learner self-reported (all tasks)**  
**Evidence level:** Learner confirmation; original terminal output/screenshots and independently executed results are not included in this repository entry.

> **Purpose:** Create a MySQL database and SQL dump, store the dump in a persistent named volume, restore it into a **different MySQL container**, and query the restored records. All instructor tasks and commands are documented below, including an important correction to Task 3.2. For internals, failure modes, security, backups, recovery objectives and interviews, see [DEEP-DIVE.md](DEEP-DIVE.md).

## Objectives

- Implement data backup strategies for stateful containers.
- Perform database dumps inside containers.
- Store dumps on persistent Podman named volumes.
- Restore a database from a stored SQL dump and verify the data.

## Prerequisites

- Podman 3.0+; access to a Linux host/VM and a terminal.
- Internet access to pull `docker.io/library/mysql:8.0` and Alpine.
- Basic understanding of containers, SQL and filesystem redirection.
- Sufficient free disk space for images and backups.
- **Use disposable lab credentials only.** Example passwords are intentionally visible in the course exercise; they are not production secrets.

## Lab setup — both instructor commands

```bash
podman --version
mkdir -p ~/backup-lab && cd ~/backup-lab
```

The command `cd ~/backup-lab` matters: `testdb_dump.sql` is written in the **current host directory**, not inside the database container. Run subsequent shell commands from this directory unless stated otherwise.

**Name-collision note:** The instructor calls the source container `mysql-db`, which was also used in Lab 11. If a container with that name already exists, **do not delete it blindly**. Either finish/stop and remove it only after safeguarding its data, or consistently substitute a fresh name such as `mysql-backup-src` in every source-container command below. The commands in this runbook preserve the instructor's original `mysql-db` name.

---

## Task 1 — Perform database dumps inside a container

### Subtask 1.1 — Create a MySQL container

**Instructor command (complete):**

```bash
podman run -d --name mysql-db \
  -e MYSQL_ROOT_PASSWORD=redhat \
  -e MYSQL_DATABASE=testdb \
  -e MYSQL_USER=testuser \
  -e MYSQL_PASSWORD=testpass \
  docker.io/library/mysql:8.0
```

**Instructor verification:**

```bash
podman ps -f name=mysql-db
```

`-d` detaches; `MYSQL_DATABASE`, `MYSQL_USER`, and the passwords configure the **initialization of a fresh database directory**. A running container is not necessarily ready for connections immediately.

**Recommended readiness check (additional):**

```bash
podman logs mysql-db
podman exec mysql-db mysqladmin ping -u root -predhat
```

Wait until initialization completes. These are diagnostic instructions, not a claim that the learner captured these outputs.

### Subtask 1.2 — Create sample data

**1. Open the MySQL client inside the container:**

```bash
podman exec -it mysql-db mysql -u root -predhat
```

**2. Run all instructor SQL statements in the MySQL prompt:**

```sql
USE testdb;
CREATE TABLE employees (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(50));
INSERT INTO employees (name) VALUES ('John Doe'), ('Jane Smith');
SELECT * FROM employees;
```

**Expected result (illustrative):**

```text
+----+------------+
| id | name       |
+----+------------+
|  1 | John Doe   |
|  2 | Jane Smith |
+----+------------+
```

**3. Exit the MySQL client:**

```sql
exit
```

**Why it matters:** These two inserted records become the verification target for the later restore test. `exit` returns you to the host terminal before you create the dump.

### Subtask 1.3 — Create a database dump

**Instructor command (complete):**

```bash
podman exec mysql-db /usr/bin/mysqldump -u root -predhat testdb > testdb_dump.sql
```

**Instructor verification commands:**

```bash
ls -l testdb_dump.sql
head -n 5 testdb_dump.sql
```

**Extra useful checks (not part of the instructor's exact commands):**

```bash
test -s testdb_dump.sql && echo "SQL dump is non-empty"
grep -n 'John Doe' testdb_dump.sql
```

**Key insight:** `mysqldump` executes **inside** `mysql-db`, but the shell's `>` redirection runs **on the host**; therefore `~/backup-lab/testdb_dump.sql` is a host file. Viewing only the first five lines does not prove every SQL row was exported. The true restore verification comes in Task 3.

---

## Task 2 — Store dumps on volumes

### Subtask 2.1 — Create a persistent named volume

**Instructor command:**

```bash
podman volume create backup-vol
```

This Podman-managed named volume persists beyond removal of the temporary containers that access it, unless explicitly removed or pruned.

### Subtask 2.2 — Copy the dump into the volume

**Step 1 — Instructor command: Start an interactive temporary Alpine container:**

```bash
podman run -it --rm -v backup-vol:/backup alpine sh
```

**Step 2 — Inside the Alpine shell, run both lines:**

```sh
mkdir -p /backup/mysql
exit
```

The Alpine container is removed by `--rm`; the `backup-vol` named volume remains.

**Step 3 — Instructor's exact copy and cleanup commands (shown for completeness):**

```bash
podman cp testdb_dump.sql $(podman create --name temp -v backup-vol:/backup alpine):/backup/mysql/
podman rm temp
```

This uses command substitution to create a stopped temporary container named `temp`, copies the host SQL dump into its mounted volume path, then removes the temporary container. This approach is compact but difficult to troubleshoot, and behavior may vary with container mount handling.

**Clearer alternative, with explicit commands (use when needed):**

```bash
podman create --name temp -v backup-vol:/backup docker.io/library/alpine
podman cp testdb_dump.sql temp:/backup/mysql/
podman rm temp
```

**Reliable streaming alternative (if copying into a stopped container fails):**

```bash
podman run --rm -i -v backup-vol:/backup docker.io/library/alpine \
  sh -c 'mkdir -p /backup/mysql && cat > /backup/mysql/testdb_dump.sql' \
  < testdb_dump.sql
```

**Do not run all three alternatives:** the instructor version, expanded `podman cp` version, and stream version are *alternative ways to perform the same transfer*. If `temp` exists from a failed attempt, inspect or remove only that lab-created temporary container before retrying.

**Instructor verification (exact):**

```bash
podman run --rm -v backup-vol:/backup alpine ls -l /backup/mysql
```

**Additional content check (optional):**

```bash
podman run --rm -v backup-vol:/backup:ro docker.io/library/alpine \
  sh -c 'test -s /backup/mysql/testdb_dump.sql && grep -n "John Doe" /backup/mysql/testdb_dump.sql'
```

**Interpretation:** The backup copy is now located at `/backup/mysql/testdb_dump.sql` as seen from a helper container and backed by `backup-vol`. The host's original `testdb_dump.sql` also exists unless you remove it.

---

## Task 3 — Restore data from dumps

### Subtask 3.1 — Create a new MySQL container

**Instructor command (complete):**

```bash
podman run -d --name mysql-restore \
  -e MYSQL_ROOT_PASSWORD=redhat \
  -e MYSQL_DATABASE=testdb \
  -e MYSQL_USER=testuser \
  -e MYSQL_PASSWORD=testpass \
  docker.io/library/mysql:8.0
```

This is a **new independent MySQL instance**. It does **not** mount the source container's data directory. The restored records must arrive through the logical SQL backup.

**Recommended additional readiness check:**

```bash
podman exec mysql-restore mysqladmin ping -u root -predhat
```

### Subtask 3.2 — Recover the dump from the volume, then restore it

**Instructor's original dump-copy commands (documented verbatim; do not rely on these as written):**

```bash
podman run --rm -v backup-vol:/backup alpine cp /backup/mysql/testdb_dump.sql /tmp/
podman cp $(podman create --name temp -v backup-vol:/backup alpine):/tmp/testdb_dump.sql .
podman rm temp
```

**Why these commands are broken:** The first command copies into `/tmp` in a short-lived Alpine container, then `--rm` deletes that container and its private `/tmp` data. The next command creates an entirely different container and tries to read `/tmp/testdb_dump.sql` from it. The named volume stores the file at `/backup/mysql/`, **not** `/tmp/`. Therefore, the original sequence does not reliably recover the backup.

**Correct, working restore-from-volume flow (recommended):**

```bash
# Copy SQL from the mounted named volume to a new file on the host.
podman run --rm -v backup-vol:/backup:ro docker.io/library/alpine \
  cat /backup/mysql/testdb_dump.sql > testdb_dump_from_volume.sql

# Verify this backup file exists and contains data.
ls -l testdb_dump_from_volume.sql
test -s testdb_dump_from_volume.sql && echo "Recovered backup is non-empty"

# Restore into the NEW MySQL instance.
podman exec -i mysql-restore mysql -u root -predhat testdb < testdb_dump_from_volume.sql
```

**Original instructor restore command (also valid when `testdb_dump.sql` is available on the host):**

```bash
podman exec -i mysql-restore mysql -u root -predhat testdb < testdb_dump.sql
```

The command above restores from the **host's original dump**, so by itself it does *not* prove retrieval from `backup-vol`. Prefer `testdb_dump_from_volume.sql` for the full Task 2 → Task 3 evidence chain. `-i` leaves STDIN attached to feed SQL into MySQL; the shell's `<` reads the chosen SQL file on the host. A successful import often produces no terminal output.

### Subtask 3.3 — Verify restoration

**Instructor command (exact):**

```bash
podman exec -it mysql-restore mysql -u root -predhat -e "SELECT * FROM testdb.employees;"
```

**Expected output (example, not a captured learner log):**

```text
+----+------------+
| id | name       |
+----+------------+
|  1 | John Doe   |
|  2 | Jane Smith |
+----+------------+
```

**Success criteria:** The two original names appear in the new `mysql-restore` instance. This shows that a logical SQL backup can recover the sample data into an independent database container, assuming the dump is valid and the restore succeeds.

---

## Troubleshooting — all instructor tips included

### 1. Source MySQL container fails to start

```bash
podman logs mysql-db
```

Check image pull, startup initialization, database credentials, disk space, memory, and existing container-name conflicts. For the restore database, also check `podman logs mysql-restore`.

### 2. Permission issues with a volume

**Instructor's example mount option:**

```bash
-v backup-vol:/backup:Z
```

On SELinux hosts, `:Z` is mainly important for **host bind mounts** requiring private relabeling; Podman-managed named volumes are normally handled by Podman's labeling. Do not blindly relabel a volume shared with other containers. Review actual permissions, SELinux denials, and rootless UID mappings before changing ownership or labels.

### 3. Dump failure

Confirm database credentials, the `testdb` name, and whether the MySQL service is ready. Verify file size after export, because `>` can leave an empty host file if `mysqldump` fails.

**Additional common problems:**

| Symptom | Likely cause / response |
| --- | --- |
| `container name already in use` | Lab 11's `mysql-db` still exists; choose a unique name or safely resolve the collision |
| `mysql: connection refused` / initialization not ready | Wait for database readiness and inspect `podman logs` |
| `temp` name already exists | A previous copy attempt left `temp`; inspect it, then remove that specific temporary container |
| `no such file /tmp/testdb_dump.sql` | Instructor Task 3.2 copies into ephemeral `/tmp`; use the corrected volume-reading command |
| Empty dump file | Check `mysqldump` exit status/credentials and redo export before restore |
| `Table 'employees' already exists` | You may have imported the dump into the same database twice; use a fresh restore instance for repeatable testing |
| MySQL image pull fails | Check network/registry access and disk space |

---

## Lab conclusion

**Completed — self-reported.** The learner has confirmed all Lab 12 tasks were performed, including backup generation, named-volume storage, dump restoration and record verification. Documentation provides reproducible steps and *expected* results; no original session output, logs or screenshots are being presented as independent proof.

Key capabilities practiced:

1. Created a MySQL database in a container.
2. Generated a logical SQL backup using `mysqldump`.
3. Stored the dump on a Podman-managed persistent named volume.
4. Restored the backup into a separate MySQL container.
5. Verified the two original records with `SELECT`.

**Important limitation:** A named volume on the **same host** is not a complete disaster-recovery plan. Separate copies, tested restores and appropriate storage security are needed for production.

## Cleanup — instructor's exact commands

**⚠️ Destructive:** Only run if you no longer need the two lab containers and the `backup-vol` backup. Do not delete the only remaining copy of valuable data.

```bash
podman stop mysql-db mysql-restore
podman rm mysql-db mysql-restore
podman volume rm backup-vol
rm -f testdb_dump.sql
```

If you used the safer alternate source container name `mysql-backup-src`, substitute it for `mysql-db` in the cleanup. If you generated `testdb_dump_from_volume.sql`, it remains on the host until you intentionally delete it. Removing `backup-vol` destroys the named-volume copy of the SQL dump.

## Relevant next experiments (optional, not required for Lab 12)

- Export with consistency options appropriate to the MySQL storage engine.
- Store encrypted backups off-host and test restore procedures regularly.
- Record real timestamps, commands, output and anonymized screenshots in an evidence journal.
- Compare logical SQL backups with raw volume/file-system backups and database-native snapshot methods.

---

**Further reading:** [DEEP-DIVE.md](DEEP-DIVE.md) · [All Red Hat 1 labs](../LABS-INDEX.md) · [Engineering proof-of-work standards](../../evidence/PROOF-OF-WORK.md)
