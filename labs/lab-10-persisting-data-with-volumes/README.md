# Lab 10 — Persisting Data with Volumes

**Track:** Domain 5 → Linux and Open Source → Red Hat 1  
**Tool:** Podman on Linux (RHEL recommended)  
**Status:** **Completed — self-reported by learner on 20 October 2026**  
**Guide type:** Practical lab runbook + quick revision  
**Deep technical notes:** [DEEP-DIVE.md](DEEP-DIVE.md)

> **Evidence integrity:** The learner confirmed completion of the lab. The commands and output below are a reproducible guide and **expected examples**, not saved terminal transcripts or independently verified execution logs. If screenshots or actual logs are later published, link them to the relevant task. This is a training lab, not a production data-recovery guarantee.

## 1. Lab objective — what problem does this solve?

A container's writable layer belongs to that particular container. If the container is removed, changes made **only** in that writable layer are lost. Persistent mounts separate important files from the container's lifecycle so that a replacement container can access them.

This lab demonstrates **two mechanisms**:

1. **Podman-managed named volume** — `myapp_data` survives removal of `webapp` and is attached to `webapp_new`.
2. **Host bind mount** — `~/host_data` is visible inside `bind_example`; edits on the host are visible from the container.

### Learning objectives (all four)

- [x] Configure persistent container storage with volumes — learner-confirmed
- [x] Create and manage a named volume — learner-confirmed
- [x] Attach the named volume to containers and demonstrate persistence — learner-confirmed
- [x] Mount a host directory and observe live changes — learner-confirmed

## 2. Prerequisites

- Basic command-line knowledge.
- Podman installed (the training material recommends **3.0+**).
- Linux host such as RHEL; WSL2 is an alternative if running on Windows.
- Rootless Podman is optional and recommended for a smaller privilege footprint.
- Network access to pull `docker.io/library/nginx` on first use.

Optional installation check (not a task from the original handout):

```bash
podman --version
```

**Execution convention:** Run all original commands below as the **same Linux user** with the same Podman context. `sudo podman` and rootless `podman` normally use different container/volume stores.

## 3. Task 1 — Creating Named Volumes

**Concept:** A named volume is managed by Podman and can outlive any individual container which mounts it.

### Subtask 1.1 — Create a named volume

**Original command:**

```bash
podman volume create myapp_data
```

**Expected output:**

```text
myapp_data
```

**Original verification command:**

```bash
podman volume ls
```

**Verify:** The volume list includes `myapp_data`. The create command names the volume; it does not create a container.

### Subtask 1.2 — Inspect the volume

**Original command:**

```bash
podman volume inspect myapp_data
```

**Illustrative expected output from the lab material (not an actual saved result):**

```json
[
  {
    "Name": "myapp_data",
    "Driver": "local",
    "Mountpoint": "/var/lib/containers/storage/volumes/myapp_data/_data",
    "CreatedAt": "2023-10-05T12:00:00Z",
    "Labels": {},
    "Scope": "local"
  }
]
```

**What to inspect:**

| Field | Meaning |
| --- | --- |
| `Name` | Podman volume identifier (`myapp_data`) |
| `Driver` | Volume implementation, commonly `local` |
| `Mountpoint` | Host-side directory backing the volume |
| `CreatedAt` | Creation timestamp when reported |
| `Labels` | Any metadata labels associated with the volume |
| `Scope` | Volume availability scope when reported |

**Important:** The `Mountpoint`, timestamp, and JSON fields may differ. `/var/lib/containers/storage/volumes/...` is typical of **rootful** Podman. With **rootless** Podman the path is commonly under `~/.local/share/containers/storage/volumes/...`; use the actual inspected value, not the sample value.

**Task 1 verification criterion:** `myapp_data` appears in `podman volume ls`, and `podman volume inspect` shows its details.

---

## 4. Task 2 — Mounting Volumes in Containers

**Concept:** Mount the same named volume into two successive containers, and verify the file still exists after removing the first container.

### Subtask 2.1 — Run a container with a volume

**Original command:**

```bash
podman run -d --name webapp -v myapp_data:/var/www/html docker.io/library/nginx
```

**Flags and arguments:**

- `podman run`: create and start a container.
- `-d`: detached mode; Nginx runs in the background.
- `--name webapp`: name of the first container.
- `-v myapp_data:/var/www/html`: attach the named volume at `/var/www/html` **inside** the container.
- `docker.io/library/nginx`: official Nginx image.

**Original verification command:**

```bash
podman exec webapp ls /var/www/html
```

**Expected:** No listed files **if the named volume is genuinely empty**. An already populated volume or image-specific initialization can make this output different. `podman exec` requires `webapp` to be running.

> **Nginx path detail:** This task intentionally stores data under `/var/www/html` for a persistence test. The official Nginx image normally serves web pages from **`/usr/share/nginx/html`**, so the original command is **not** itself a web-serving test. No host port is published here. We verify the data with `podman exec`, exactly as the lab requests.

### Subtask 2.2 — Persist data in the volume

**Original write command:**

```bash
podman exec webapp sh -c "echo 'Hello, Volume!' > /var/www/html/index.html"
```

**Original read/verification command:**

```bash
podman exec webapp cat /var/www/html/index.html
```

**Expected output:**

```text
Hello, Volume!
```

**Why `sh -c`?** The `>` redirection must be evaluated by a shell **inside** the container. Because `/var/www/html` is a mount, this writes into `myapp_data`, not merely into the container's disposable writable layer. `>` overwrites the file's existing contents.

### Subtask 2.3 — Verify persistence after container replacement

**Original step 1 — remove the first container:**

```bash
podman rm -f webapp
```

`-f` forces removal (and stops a running container if needed). This removes `webapp`; it does **not** automatically delete the separately named volume `myapp_data`.

**Original step 2 — create a new container using the SAME volume:**

```bash
podman run -d --name webapp_new -v myapp_data:/var/www/html docker.io/library/nginx
```

**Original step 3 — read the saved data:**

```bash
podman exec webapp_new cat /var/www/html/index.html
```

**Expected output:**

```text
Hello, Volume!
```

**What this demonstrates:** `webapp` was removed, `webapp_new` is a new container, and the same named volume preserves `index.html` between them. This is **container replacement persistence**, not a substitute for off-host backups or recovery from disk/VM failure.

**Task 2 verification criterion:** The exact `Hello, Volume!` content is present before and after removing/recreating the container.

---

## 5. Task 3 — Using Bind Mounts with Host Directories

**Concept:** A bind mount exposes a specific host directory at a path inside a container. Changes made on either side may be visible to the other, subject to permissions, SELinux policy and read/write mount settings.

### Subtask 3.1 — Create a host directory and file

**Original commands:**

```bash
mkdir ~/host_data
echo "Hello, Bind Mount!" > ~/host_data/index.html
```

`mkdir` makes the directory in the current user's home. The `echo` writes `index.html` on the **host**, before any container is created. If `~/host_data` already exists, `mkdir` may report `File exists`; inspect the existing directory before changing it. (The commands above are preserved exactly from the original lab.)

### Subtask 3.2 — Run with a bind mount

**Original command:**

```bash
podman run -d --name bind_example -v ~/host_data:/usr/share/nginx/html:Z docker.io/library/nginx
```

**Mount anatomy:**

- `~/host_data` — source directory on your Linux **host** (`~` is expanded by the shell).
- `/usr/share/nginx/html` — directory **inside** the Nginx container; it is the image's normal web document root.
- `:Z` — ask Podman to apply a **private SELinux relabel** suitable for this container on SELinux-enforcing systems such as RHEL.
- `docker.io/library/nginx` — image used for the test.

**Original verification command:**

```bash
podman exec bind_example cat /usr/share/nginx/html/index.html
```

**Expected output:**

```text
Hello, Bind Mount!
```

**Safety note:** `:Z` can recursively relabel the host source. Use it on this dedicated lab directory, not casually on system directories or shared sensitive paths. For certain explicitly shared SELinux mounts, `:z` has different semantics. SELinux is one possible cause of a permission error, not the only cause.

### Subtask 3.3 — Modify host data and verify

**Original host-side append command:**

```bash
echo "Updated content!" >> ~/host_data/index.html
```

Here `>>` appends a new line; unlike `>` it does not replace the original line.

**Original container-side verification command:**

```bash
podman exec bind_example cat /usr/share/nginx/html/index.html
```

**Expected output:**

```text
Hello, Bind Mount!
Updated content!
```

**What this demonstrates:** The host and container reference the same mounted files. The changed content becomes visible to the container without rebuilding its image or recreating it.

**Task 3 verification criterion:** `bind_example` initially reads `Hello, Bind Mount!`; after the host edit it reads both lines.

---

## 6. Quick revision — all original lab commands, in execution order

This command reference intentionally includes **every command from Task 1 through Task 3**, in the same order as the supplied lab. Run them on a suitable system; **`podman rm -f webapp` removes that named container**.

```bash
# Task 1 — Subtask 1.1: create and list the named volume
podman volume create myapp_data
podman volume ls

# Task 1 — Subtask 1.2: inspect the named volume
podman volume inspect myapp_data

# Task 2 — Subtask 2.1: create first container and inspect mount contents
podman run -d --name webapp -v myapp_data:/var/www/html docker.io/library/nginx
podman exec webapp ls /var/www/html

# Task 2 — Subtask 2.2: write and verify persistent data
podman exec webapp sh -c "echo 'Hello, Volume!' > /var/www/html/index.html"
podman exec webapp cat /var/www/html/index.html

# Task 2 — Subtask 2.3: delete and replace container; verify persistence
podman rm -f webapp
podman run -d --name webapp_new -v myapp_data:/var/www/html docker.io/library/nginx
podman exec webapp_new cat /var/www/html/index.html

# Task 3 — Subtask 3.1: prepare host-side directory and file
mkdir ~/host_data
echo "Hello, Bind Mount!" > ~/host_data/index.html

# Task 3 — Subtask 3.2: mount host directory and read file in container
podman run -d --name bind_example -v ~/host_data:/usr/share/nginx/html:Z docker.io/library/nginx
podman exec bind_example cat /usr/share/nginx/html/index.html

# Task 3 — Subtask 3.3: append on host; read updated file in container
echo "Updated content!" >> ~/host_data/index.html
podman exec bind_example cat /usr/share/nginx/html/index.html
```

## 7. Troubleshooting reference (all topics from the lab)

| Issue | What to verify | What to do |
| --- | --- | --- |
| SELinux / `Permission denied` | `:Z` private relabel or `:z` shared relabel; source/destination and DAC permissions | Use appropriate SELinux labeling for a **dedicated** directory. Check rootless UID/GID mappings; do not blindly disable SELinux. |
| Volume not found | `podman volume ls` | Create `myapp_data` in the same Podman (rootless/rootful) context, then retry. |
| Bind mount path wrong | Host path, shell `~` expansion, exact destination inside image | Prefer an **absolute host path**; verify it refers to the intended directory. |
| Container name already in use | Existing `webapp`, `webapp_new`, or `bind_example` | Inspect the existing container before deciding whether to remove it. |
| `podman exec` fails | Container might not be running | Inspect status/logs and actual error before retrying. |
| Volume read works but browser doesn't show page | Task 2 mounts `/var/www/html`, not Nginx's default web root; no `-p` | Persistence verification with `cat` is still valid; web serving needs the proper mount destination and published port. |

Optional diagnostic commands (not part of the instructor's Task 1–3 command sequence):

```bash
podman ps -a
podman volume ls
podman logs webapp_new
podman logs bind_example
```

## 8. Conclusion — what this lab established

- **Named volumes** are reusable Podman-managed storage resources and are separate from container removal.
- `-v myapp_data:/var/www/html` links named persistent storage into the container.
- Mounting the **same volume** into a replacement container preserves the file across removal of the previous container.
- Bind mounts share actual host-directory content with the container; appending to the host file is reflected inside the container.
- `:Z` matters for private bind mounts on SELinux-enabled systems such as RHEL.

**Production boundary:** Local persistence is not a verified backup or high-availability architecture. For databases and critical state, consider application-aware backups, tested restores, access permissions, host failures, and storage platform design.

## 9. Next steps (all original suggestions retained)

1. **Explore `podman volume prune`** to remove unused volumes, but **do not run it blindly**: it can delete persistent data you meant to keep. Inspect target volumes first.
2. Try persistent volumes with a database such as PostgreSQL or MySQL, using the image's real data directory and an application-consistent backup strategy.
3. Learn network-oriented volume drivers / storage such as NFS, including permissions, reliability and multi-host constraints.

## 10. Optional targeted cleanup — NOT part of the original instructor tasks

Do **not** remove the named volume if you want to keep this lab's stored data. When ready to clean up only the containers created by this lab:

```bash
podman rm -f webapp_new bind_example
```

If you intentionally want to permanently delete the named volume **and its data**, after ensuring no other container needs it:

```bash
podman volume rm myapp_data
```

The original lab did **not** direct you to delete `~/host_data`; that directory is host data and remains unless you explicitly remove it. Avoid broad prune commands and deleting other lab resources.

## 11. Evidence record

| Item | Status |
| --- | --- |
| Task 1 — named volume creation and inspect | **Completed — learner-confirmed** |
| Task 2 — write, remove, recreate, and read | **Completed — learner-confirmed** |
| Task 3 — host bind mount and live edit | **Completed — learner-confirmed** |
| Attached original screenshot / terminal transcript | **Not supplied in this documentation** |
| Independent runtime verification | **Not performed as part of preparing these docs** |

For repository-wide evidence methodology, see [Engineering Proof of Work](../../evidence/PROOF-OF-WORK.md). For full conceptual explanations, see **[DEEP-DIVE.md](DEEP-DIVE.md)**. Back to the [Red Hat 1 lab index](../LABS-INDEX.md).
