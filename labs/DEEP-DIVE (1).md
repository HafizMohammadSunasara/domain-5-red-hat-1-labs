# Lab 10 — Deep Dive: Persistent Container Storage with Podman

**Track:** Domain 5 → Linux and Open Source → Red Hat 1  
**Companion:** [Practical Lab README — every instructor task and command](README.md)  
**Audience:** Self-revision, junior Cloud/DevOps engineers and technical reviewers  
**Lab status:** Completed — learner-confirmed, 20 October 2026  
**Evidence standard:** Explanations, diagrams, example outputs and proposed diagnostics are **not** historical execution logs.

## 1. The problem: what happens to data when containers are replaced?

A container image is a reusable template. A running container adds a **writable layer** above the image's read-only layers. Applications may write temporary files, logs, uploaded content or a database to this layer. When **that container is removed**, its private writable layer is removed too.

A restart of the **same** existing container is different from deleting it: the writable layer normally remains across ordinary stop/start operations. Our experiment deliberately removes the old container and creates a **different** one, making the distinction visible.

```text
WITHOUT PERSISTENT STORAGE

  Image (reusable)
      |
      v
  Container A + writable layer --> /app/file.txt
      |
      | podman rm -f containerA
      v
  Container A's writable layer is removed
      |
      v
  Container B from same image --> file.txt is NOT inherited

WITH A NAMED VOLUME

  Container A ---- mounts ----+
                             |
                         [myapp_data]
                         index.html
                             |
  remove Container A         |  <-- Volume remains on host
                             |
  Container B ---- mounts ----+
                             |
                             v
                    reads same index.html
```

**Core idea:** A volume or bind mount is not another image layer. It is storage exposed at a container path, independent of the disposable instance's writable layer.

> **Scope of persistence:** The volume data stays available across a **container replacement**, provided the underlying host/VM storage persists and the volume itself isn't removed. Volumes alone do not provide disaster recovery, remote backups, or availability across separate hosts.

## 2. Three places a container may store a file

| Where the write happens | Example destination | Lifetime / behavior |
| --- | --- | --- |
| Container writable layer | `/tmp/new-file` without a mount | Survives ordinary stop/start of the same container, but is lost when that container is removed |
| Podman named volume | `myapp_data:/var/www/html` | Data belongs to a separately managed named volume; new containers can mount it |
| Host bind mount | `~/host_data:/usr/share/nginx/html:Z` | Container directly accesses a specified host directory; content persists in the host directory |

Both named volumes and bind mounts ultimately rely on real storage. The distinction is **who selects/manages the backing location**.

## 3. Named volumes: who creates and owns the mount location?

The command:

```bash
podman volume create myapp_data
```

asks Podman to register a local volume with a stable name. The operator uses that logical name in subsequent commands instead of hardcoding its internal storage path.

```bash
podman volume ls
podman volume inspect myapp_data
```

The inspection output typically describes the volume's `Name`, `Driver`, `Mountpoint` and optional metadata such as time/labels. The training material illustrates a path below:

```text
/var/lib/containers/storage/volumes/myapp_data/_data
```

That's commonly a **rootful** Podman location. On rootless Podman, local storage is typically below the user's own directory (for example `~/.local/share/containers/storage/volumes/...`). Actual location can differ with version, storage config and runtime setup.

### Rootless vs rootful — the often-missed detail

On the same Linux machine:

- `podman volume ls` run **without** `sudo` lists that user's rootless volume store.
- `sudo podman volume ls` looks in the rootful Podman store.

Consequently, creating a volume with one context and looking for it in the other can make it appear as if it vanished. Do not mix contexts across this lab.

### `local` driver does not mean global persistence

`Driver: local` normally means storage is local to this host. There is **no automatic replication** to another machine. If a VirtualBox VM disk is lost or deleted, a local volume on that VM is at risk too. For production, plan separate backups and recovery.

### Mental model

Think of a named volume like a **locker identified by its name**. You can remove the person using the locker (container) and let someone else (new container) use the same locker. If you delete the locker itself (volume), its contents can be lost.

## 4. Task 2, explained deeply: write → remove → recreate → read

### 4.1 Attach the volume to the first Nginx container

```bash
podman run -d --name webapp -v myapp_data:/var/www/html docker.io/library/nginx
```

At runtime, the container sees the volume's filesystem at `/var/www/html`. The `-v SOURCE:DESTINATION` notation means:

```text
SOURCE:       myapp_data                 (Podman-managed named volume)
COLON:        :                          (mapping separator)
DESTINATION:  /var/www/html              (path within container)
```

`--name webapp` identifies the container. `-d` detaches from its terminal and **doesn't force a process to stay running**. Nginx happens to start a long-running service when functioning correctly.

#### Expected contents of the mount

```bash
podman exec webapp ls /var/www/html
```

The lab expects no output for a new, empty volume. That expectation depends on the environment and whether the same volume was already used. Some volume implementations/image combinations may initialize a fresh volume with pre-existing container-directory contents. Use inspection rather than claiming a directory must always be empty.

### 4.2 Write inside the container, but store outside the disposable layer

```bash
podman exec webapp sh -c "echo 'Hello, Volume!' > /var/www/html/index.html"
podman exec webapp cat /var/www/html/index.html
```

This command is worth understanding in stages:

1. `podman exec webapp` runs a **new process inside an existing running container**.
2. `sh -c '...'` invokes a shell to interpret shell syntax. Here the outer shell passes a correctly quoted string to `sh -c`.
3. `echo 'Hello, Volume!'` produces a text line.
4. `>` opens `/var/www/html/index.html` for writing, **replacing** any previous contents.
5. Because `/var/www/html` is a **mounted volume destination**, the write reaches the volume-backed filesystem.
6. `cat` confirms the readable contents from inside `webapp`.

Expected output:

```text
Hello, Volume!
```

This also explains why `podman exec webapp echo Hello > /var/www/html/index.html` typed on a host terminal would be a different operation: without the inner `sh -c`, the `>` redirection would be evaluated by the **host's shell** before Podman runs. The instructor's syntax deliberately puts redirection in the container.

### 4.3 Delete the container; retain the volume

```bash
podman rm -f webapp
```

This removes **that named container** and its writable layer; it is not a request to delete `myapp_data`. The `-f` flag is destructive to the specified container, so it should not be casually used against valuable running workloads.

### 4.4 Recreate a completely new container

```bash
podman run -d --name webapp_new -v myapp_data:/var/www/html docker.io/library/nginx
podman exec webapp_new cat /var/www/html/index.html
```

The new name `webapp_new` matters only as a way to refer to the replacement container. **What matters for persistence is the identical source volume name: `myapp_data`.**

Expected result:

```text
Hello, Volume!
```

This is the main practical proof pattern: write data, delete the writing container, make a new container with the *same volume*, and observe that the data remains.

### Does the Nginx browser show this file?

**Not with the instructor's original command alone.** The official `docker.io/library/nginx` image normally serves static content from:

```text
/usr/share/nginx/html
```

The named volume lab attaches to:

```text
/var/www/html
```

Also, the original command has no published host port (no `-p`). That's **not an error in the persistence test**: the instructor validates by running `cat` with `podman exec`, not by opening a web browser.

**Optional extension — NOT an original lab task:** To also *serve* the same named-volume file as an Nginx webpage, use the image's correct document root and publish a host port:

```bash
podman run -d --name webapp_http -p 8080:80 -v myapp_data:/usr/share/nginx/html docker.io/library/nginx
curl http://127.0.0.1:8080
```

Expected in a working environment: `Hello, Volume!` returned by Nginx. The command is illustrative and **not reported as executed**; it may require free port 8080, working network/SELinux permissions and a ready Nginx server. It runs *on the host where Podman is installed*, so with a remote/VM host the browser/network path needs extra consideration. Stop this optional container by name when you no longer need it; do not blindly prune volumes.

## 5. Bind mounts: same file, two views

Named volume: you pass **a volume name**. Bind mount: you pass a **specific existing host directory path**.

### 5.1 First create the file on the host

```bash
mkdir ~/host_data
echo "Hello, Bind Mount!" > ~/host_data/index.html
```

In Linux shells, `~` in this unquoted position normally expands to the invoking user's home, such as `/home/student`. `>` creates or replaces the host file.

**Practical nuance:** The first `mkdir` command may fail if `~/host_data` already exists from a previous run. That doesn't necessarily invalidate the lab; check what exists before overwriting. This is one reason real runbooks often add guards, while our practical README keeps the **instructor's exact** command.

### 5.2 Map the directory into the container

```bash
podman run -d --name bind_example -v ~/host_data:/usr/share/nginx/html:Z docker.io/library/nginx
podman exec bind_example cat /usr/share/nginx/html/index.html
```

Diagram:

```text
           RHEL / LINUX HOST                          NGINX CONTAINER

  ~/host_data/index.html                               /usr/share/nginx/html/index.html
  Hello, Bind Mount!           <-- same bind mount --> Hello, Bind Mount!
              |                                            |
     You edit from Linux CLI                     `podman exec` reads file
```

Mounting a directory at the Nginx document root means it may also serve that file over HTTP **if** an appropriate port is published and Nginx has permission. The instructor does not publish one here, so validation stays CLI-based.

### 5.3 Modify the host file while the container stays running

```bash
echo "Updated content!" >> ~/host_data/index.html
podman exec bind_example cat /usr/share/nginx/html/index.html
```

Expected output:

```text
Hello, Bind Mount!
Updated content!
```

Here `>>` means **append**, unlike the earlier `>` overwrite. The container reads the same host-backed filesystem, so the change is immediately available. Applications that cache content might need refresh/reload to *display* a change, but the file itself is updated.

### Why is this useful in development?

- Edit website source code on a host; the container sees updated files without rebuilding the image.
- Mount a dedicated configuration folder for an application.
- Keep a controlled work directory separate from the container lifecycle.

**Important production caveat:** Changing host files underneath a container may introduce security, reproducibility and consistency risks. For immutable releases, baking static application code into a versioned image is often more predictable, while volumes are more suitable for genuinely mutable state.

## 6. SELinux: what exactly does `:Z` mean on RHEL?

Linux file access can be limited by traditional ownership/mode bits **and** mandatory access control such as SELinux. A process running inside an SELinux-confined container might get `Permission denied` even when the directory's normal Unix mode bits appear permissive.

Bind mount syntax:

```text
-v ~/host_data:/usr/share/nginx/html:Z
```

`Z` (uppercase) asks Podman to relabel the bind-mounted host content for **private** use by this container. A lowercase `z` asks for a **shared** container-access label suitable for certain multi-container sharing cases.

| Label | Concept | Typical consideration |
| --- | --- | --- |
| `:Z` | Private SELinux relabel | Suitable for a dedicated path owned by one container |
| `:z` | Shared SELinux relabel | May help when the same labeled host content is meant to be shared by several containers |
| No suffix | Leave labels unchanged | May work in some setups but can be denied on enforcing SELinux hosts |

**Don't equate SELinux relabeling with normal file permissions.** You can still have ownership/UID mapping restrictions under rootless Podman even when the SELinux label is correct.

**Safety:** Relabel only a **dedicated lab directory**; private relabeling a home directory, system tree or host service directory may disrupt other processes and has security implications. Do not suggest blanket `chmod 777` or turning SELinux off as a normal fix.

## 7. Named volumes vs bind mounts — how an engineer chooses

| Design question | Named volume | Bind mount |
| --- | --- | --- |
| How do I reference the source? | Logical Podman name, e.g. `myapp_data` | Explicit host directory, e.g. `/home/student/host_data` |
| Who chooses backing location? | Podman/storage configuration | Operator choosing host path |
| Easy to recreate a container with same data? | Yes, reattach same named volume | Yes, reuse same host path |
| Host editing of content | Possible, but Podman manages internal path and permissions | Convenient: source is a known host directory |
| Common fit | Stateful app data, database storage within one host | Local development, host-managed content and configuration |
| Automatic backups / host independence? | No | No |
| SELinux/rootless permissions? | Still relevant | Especially visible with bind-source ownership and `:Z`/`:z` |

Neither option is automatically "more secure" or "always production ready." The threat model, write pattern, host and deployment environment matter.

## 8. Real-world engineering scenarios

### Scenario A — Database container replacement

A PostgreSQL container usually needs its database directory stored outside the ephemeral container writable layer. Otherwise, an upgrade/replacement could destroy the only copy of its data.

A volume mounted at the **correct database image's documented data directory** can preserve it across container replacement on the same host. However:

- A **volume alone is not a database backup**.
- Raw copies during database writes may be inconsistent. Use database-aware backup/restore procedures.
- Correct UID/GID, permissions and SELinux labeling matter.
- Multi-node failover demands separate replication/storage design.

### Scenario B — User uploads

A web application accepts uploaded images. Keep uploads on dedicated persistent storage rather than depending on the container's writable layer. On a single server, a volume may suffice for a lab. At scale, object storage or a shared managed storage service may be a better architectural fit.

### Scenario C — Local web development

A developer runs Nginx with a bind-mounted local site folder. They modify `index.html` on the host; the container immediately reads the updated file. This speeds local iteration, though a production release may instead build the site into a versioned image.

### Scenario D — Kubernetes/OpenShift concept bridge

Podman's local volumes teach the separation between **container instance lifecycle** and **persistent data lifecycle**. Kubernetes/OpenShift use concepts such as PersistentVolumes and PersistentVolumeClaims, backed by storage classes/drivers. Those objects are **not identical to a local Podman volume**; claim binding, access modes, dynamic provisioning and pod scheduling introduce new design considerations.

## 9. Troubleshooting — diagnose, don't guess

### A. `Error: no volume with name myapp_data`

1. Run `podman volume ls`.
2. Check for typos and whether you changed between rootless `podman` and rootful `sudo podman`.
3. Recreate only if it is actually absent; recreating a missing volume does **not** magically recover deleted data.

### B. `permission denied`

Consider the layers separately:

- **Container process user**: is it permitted to write the destination?
- **Host directory ownership and mode**: especially with rootless UID mapping.
- **SELinux type/category**: private `:Z` versus shared `:z` bind mount.
- **Read-only setting**: did someone mount `:ro`?
- **Application path**: does Nginx or the program actually write here?

You can inspect a container's state/logs instead of indiscriminately relabeling or changing permissions:

```bash
podman ps -a
podman logs webapp_new
podman logs bind_example
```

These are supplementary diagnostics, **not** original task commands.

### C. File not visible after recreating

Check the *source* used during each `podman run`:

```text
First container:   -v myapp_data:/var/www/html
Second container:  -v myapp_data:/var/www/html
```

A typo in the volume name can lead to a different volume. The destination path must be where your validation command reads. Also verify the first write succeeded before removing the first container.

### D. `mkdir: cannot create directory ... File exists`

A repeat run may find `~/host_data` already present. First inspect what it contains. Do not delete it until you know whether the directory holds important data. The instructor used `mkdir ~/host_data` (without `-p`) and the practical README preserves it unchanged.

### E. `container name already in use`

Named containers such as `webapp_new` and `bind_example` remain after the lab unless removed. Inspect what exists and whether you still need its state; do not automatically delete unrelated workloads.

### F. Browser doesn't load the Nginx page

The original Task 2 has **two independent limitations for browser access**: it mounts `/var/www/html` rather than Nginx's usual document root, and it doesn't publish a host port. That's why it uses `podman exec ... cat` to confirm data persistence. Don't misdiagnose an HTTP problem as a broken volume.

### G. Changes to bind-mounted file don't seem visible

Verify the host location, mount destination, filename, SELinux/permissions and whether the application caches content. `podman exec ... cat` distinguishes **filesystem visibility** from **web server response behavior**.

## 10. Security, correctness and backup considerations

1. **Principle of least privilege:** Use rootless Podman where suitable, dedicated host paths and limited mount access.
2. **Read-only when appropriate:** If an application only reads configuration, consider a read-only mount in an appropriately designed setup. Do not apply this to a directory the app must write.
3. **Data integrity:** Two containers simultaneously writing to the same files require application-level coordination. Merely sharing storage doesn't solve concurrency.
4. **Backups:** Keep copies on storage independent from the VM/host, use application-consistent backup mechanisms where needed, and test restoration.
5. **Host/VM loss:** A local Podman volume disappears with its underlying storage if you lose the host or virtual disk without backup.
6. **Cleanup:** `podman volume prune` removes volumes that Podman considers unused; unused does **not** mean the data is unimportant. Never casually run it on machines storing valuable persistent data.
7. **Reproducibility:** Avoid hardcoding the system-internal named-volume mountpoint in application code; reference the stable volume name and container destination.

## 11. Interview questions + concise engineering answers

**Q1. Why does data survive `podman rm -f webapp`?**  
Because the file is in the named `myapp_data` volume, which has an independent lifecycle. `webapp_new` remounts the same volume.

**Q2. Does stopping a container always delete data?**  
No. Ordinary stop/start keeps the existing container's writable layer. Removing the container discards that container's writable layer; external volumes/bind mounts can remain.

**Q3. Named volume vs bind mount?**  
Both persist data beyond a single container. Podman manages named-volume storage; a bind mount exposes a particular path selected on the host.

**Q4. What is the difference between `>` and `>>`?**  
`>` truncates/overwrites the target file; `>>` appends. Lab 10 uses `>` when creating each initial `index.html` and `>>` when adding `Updated content!`.

**Q5. Why `sh -c` for the volume write?**  
To have the redirection `>` interpreted **inside the container** rather than by the invoking host shell.

**Q6. What does `:Z` do on RHEL?**  
It requests a private SELinux relabel for the bind-mounted source. Ownership, permissions and source safety still matter.

**Q7. Why doesn't Task 2 necessarily show `Hello, Volume!` in a browser?**  
The original mount is `/var/www/html` but official Nginx normally serves `/usr/share/nginx/html`, and no port is published.

**Q8. Does a Podman named volume protect against VM disk deletion?**  
No. Local volumes persist across *container* replacement, not loss of the underlying host/VM disk.

**Q9. Could multiple containers mount the same volume?**  
Depending on runtime/permissions, yes; but safe simultaneous writes require the application's own concurrency design and access semantics.

**Q10. Why isn't an empty `ls` result guaranteed?**  
The named volume may have previous data, and some runtimes/images initialize fresh mounts with existing target-directory contents. Always check the actual volume state.

**Q11. Does `podman volume prune` delete only broken volumes?**  
No. It targets unused volumes, which can still contain valuable data. Inspect before cleanup.

**Q12. How does this connect to OpenShift?**  
Same broad data-lifecycle principle, but OpenShift/Kubernetes use storage claims/volumes and cluster-aware provisions/access policies rather than simple host-local Podman volumes.

## 12. Full lab coverage checklist

The practical companion contains **every instructor task and command** in the original lab, including:

| Original section | Covered in practical README | Deep conceptual coverage |
| --- | --- | --- |
| Objectives, prerequisites | Yes | Storage and runtime mental models |
| 1.1 `podman volume create myapp_data` + `podman volume ls` | Yes | Named volumes / lifecycles |
| 1.2 `podman volume inspect myapp_data` | Yes, including illustrative JSON | `Mountpoint`, rootful/rootless scope |
| 2.1 `podman run ... webapp` + `podman exec ... ls` | Yes | Filesystem mounts and image docroot |
| 2.2 `podman exec ... sh -c` + `cat` | Yes | Write redirection / mount behavior |
| 2.3 `podman rm -f` + recreate + `cat` | Yes | Replacement lifecycle |
| 3.1 `mkdir` + `echo >` | Yes | Host-side source creation |
| 3.2 `podman run ... :Z` + `cat` | Yes | SELinux/private relabel |
| 3.3 `echo >>` + `cat` | Yes | Live shared file visibility |
| Troubleshooting | Yes | Permissions, volumes, paths, network |
| Conclusion | Yes | Persistence and limits |
| Next steps: prune, databases, NFS | Yes | Data safety, stateful design |

## 13. Future revision and evidence

**If you want to re-run this lab:** Follow the [README.md](README.md) task sequence. Check names/volumes first, because blindly repeating create/run commands can conflict with existing resources or overwrite files.

**If you want to provide stronger evidence:** Capture actual output showing the volume name, the original `Hello, Volume!` read, the identical read after the container replacement, and the bind mount's two-line result. Screenshots are optional and should be reviewed for sensitive information; absent screenshots must not be invented.

**If you want deeper learning:** Next try application-consistent database backups, read-only mounts, SELinux/mount ownership cases, and safe multi-container sharing. Distinguish what you experimentally verified from what is merely a proposed exercise.

---

**Core takeaway:** `myapp_data` demonstrates **container-independent local persistence**; `~/host_data` demonstrates **host–container filesystem sharing**. Both are foundational, but real operational reliability requires safe permissions, controlled writes, verified backups and clearly understood failure boundaries.

**Navigation:** [Practical runbook](README.md) · [Full lab index](../LABS-INDEX.md) · [Engineering Proof of Work](../../evidence/PROOF-OF-WORK.md)
