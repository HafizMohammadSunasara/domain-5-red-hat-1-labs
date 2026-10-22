# Lab 16 — Multi-Container Applications with Podman Compose

> **Domain 5 → Linux and Open Source → Red Hat 1** · **Status: Completed — self-reported**
>
> **Scope:** Two-service training stack: Nginx (`web`) + PostgreSQL (`db`), described and controlled through one YAML file. The learner reports completing all course tasks. **No original terminal screenshots, success logs, or independent Podman execution results are provided in this repository.** Commands and outputs below are reproducibility instructions and **expected** behavior, not recorded test evidence.

**Quick links:** [Engineering Deep Dive](DEEP-DIVE.md) · [Compose file](podman-compose.yml) · [Website HTML](html/index.html) · [All Labs](../LABS-INDEX.md) · [Proof-of-Work Policy](../../evidence/PROOF-OF-WORK.md)

## 1. Objectives

After this lab, you should be able to:

1. Define a multi-container application with Podman Compose.
2. Configure `services`, `ports`, `volumes`, and `environment` in `podman-compose.yml`.
3. Start, inspect, test, and stop the application as one Compose project.
4. Explain which project components communicate, what is (and is not) persistent, and how to debug common failures.

## 2. Prerequisites and environment checks (course lab setup)

- Linux/RHEL or WSL2; Podman 3.0+ (modern Podman recommended).
- `podman-compose` installed, via the distribution package manager where available or a suitable Python environment.
- Internet to fetch the Nginx and PostgreSQL images.
- Free host port `8080` and enough storage for pulled images.

**Original verification commands:**

```bash
podman --version
podman-compose --version
```

The course examples show `podman version 3.x.x` and `podman-compose version x.x.x`, but **your installed versions can differ**.

If `podman-compose` is not installed on an RHEL/Fedora environment, check distribution availability first:

```bash
sudo dnf install -y podman-compose
```

Use the supported distribution package or an isolated Python environment instead of blindly installing system-wide Python packages. Note that `podman compose` (with a space) is a wrapper around a separately installed Compose provider; **`podman-compose`** (hyphen) is the command used in this course.

## 3. Task 1 — Create a simple `podman-compose.yml` file

### Subtask 1.1 — Understand the basic structure

A Compose file is declarative YAML: it tells the Compose tool **what services should exist**, their images, environment variables, published ports, and filesystem mounts. A single configuration is easier to reproduce than typing separate long `podman run` commands.

Key YAML words:

| Key | Function in this lab |
| --- | --- |
| `version` | Course's legacy Compose format declaration (`'3.8'`); many newer implementations consider it obsolete. |
| `services` | Top-level map containing the `web` and `db` application services. |
| `image` | Existing image to use (no custom image build in this lab). |
| `ports` | Publish container port `80` from Nginx to host port `8080`. |
| `volumes` | Bind-mount local `./html` into Nginx's website directory. |
| `environment` | Supply PostgreSQL's first-initialization password for the training example. |

### Subtask 1.2 — Create the project and YAML

**Instructor's original setup commands** (from the parent directory):

```bash
mkdir compose-lab && cd compose-lab
touch podman-compose.yml
```

If `compose-lab` already exists, enter it rather than recreating the directory.

**Instructor's exact YAML content:**

```yaml
version: '3.8'
services:
  web:
    image: docker.io/nginx:alpine
    ports:
      - "8080:80"
    volumes:
      - ./html:/usr/share/nginx/html
  db:
    image: docker.io/postgres:13
    environment:
      POSTGRES_PASSWORD: example
```

The repository's [actual `podman-compose.yml`](podman-compose.yml) preserves the service design but makes two **explicit RHEL-friendly choices**:

- `docker.io/library/nginx:alpine` and `docker.io/library/postgres:13` identify the Docker Hub official-library images explicitly.
- `127.0.0.1:8080:80` restricts HTTP publishing to the host loopback interface; `:Z` on the `./html` bind mount adapts the mount's SELinux label for private container access. The instructor's `8080:80` can bind to more host interfaces.

**Important:** This sample intentionally **does not configure a PostgreSQL persistent volume**. The `web` service's `./html` is a **bind mount**, not a Compose-managed named volume. The `POSTGRES_PASSWORD: example` value is a disposable lab credential, **not suitable for production or a shared environment**.

**Recommended preparation before `up`** (the instructor introduces these commands later in Task 3.1; doing them first avoids starting Nginx with an empty web directory):

```bash
mkdir html
echo "<h1>Hello from Podman Compose!</h1>" > html/index.html
```

If you extracted the GitHub-ready sample, `html/index.html` already exists; do not overwrite it unless intentionally repeating the instructor's exercise. Verify:

```bash
ls -l podman-compose.yml html/index.html
```

## 4. Task 2 — Start the multi-container application

### Subtask 2.1 — Launch the application

**Instructor's original command:**

```bash
podman-compose up -d
```

**Reproducible command using this repository's specifically named file:**

```bash
podman-compose -f podman-compose.yml up -d
```

The `-f` option removes version-dependent ambiguity about which filenames are discovered automatically. Run from the folder containing `podman-compose.yml` and `html/`.

Expected effects (not exact historical output): images are pulled if absent, the Compose project network and two containers are created, and containers start in detached mode. The instructor's example also claims `compose-lab_db_data` is created, **but the supplied YAML does not declare any named `db_data` volume**; do not expect that volume based on this file alone. Image pull order, container names, and progress messages differ across Compose versions.

### Subtask 2.2 — Verify running containers

**Instructor's original command:**

```bash
podman ps
```

Expected: a container based on `nginx:alpine` and another based on `postgres:13`, both running. The sample names `compose-lab_web_1` and `compose-lab_db_1` are **not guaranteed across versions**.

Additional useful checks:

```bash
podman-compose -f podman-compose.yml ps
podman-compose -f podman-compose.yml logs web
podman-compose -f podman-compose.yml logs db
```

PostgreSQL may need initialization time even after its container reports as running. If one service exits, inspect logs rather than assuming launch succeeded.

## 5. Task 3 — Test the application

### Subtask 3.1 — Access the web service

**Instructor's original host commands (if not already run before startup):**

```bash
mkdir html
echo "<h1>Hello from Podman Compose!</h1>" > html/index.html
```

The browser URL in the course is:

```text
http://localhost:8080
```

**Instructor's verification command:**

```bash
curl http://localhost:8080
```

**Expected response** (not captured execution output):

```html
<h1>Hello from Podman Compose!</h1>
```

The default Nginx document root is `/usr/share/nginx/html`; the Compose bind mount makes the host's `./html/index.html` visible there. Changes to the host HTML file are usually immediately visible to Nginx (refresh/re-request), unlike application source changes that may require a process restart.

If you run Podman inside a VirtualBox RHEL VM, `localhost:8080` works **inside that VM**. A browser running on the Windows host may need an appropriately configured VM network or port-forwarding path; Windows `localhost` does **not automatically** address the VM.

### Subtask 3.2 — Verify the database service

**Instructor's original command:**

```bash
podman exec -it compose-lab_db_1 psql -U postgres
```

**Portable project/service alternative (preferred; no hard-coded container name):**

```bash
podman-compose -f podman-compose.yml exec db psql -U postgres
```

**Instructor's SQL commands** (enter them in the PostgreSQL `psql` session):

```sql
SELECT version();
\q
```

**Expected:** a PostgreSQL version string showing PostgreSQL 13.x, and `\q` exits the interactive shell. The exact platform/build text depends on the pulled image.

**Optional one-shot equivalent:**

```bash
podman-compose -f podman-compose.yml exec db psql -U postgres -c 'SELECT version();'
```

**Important distinction:** Nginx and PostgreSQL are deployed as two services, but this lab does **not implement an application-level Nginx-to-PostgreSQL connection**. Nginx serves static HTML and PostgreSQL responds independently to `psql` queries. PostgreSQL port 5432 is **not published to the host** by this Compose file; internal service networking is separate from host port publishing.

## 6. Task 4 — Stop and clean up

### Subtask 4.1 — Stop the application

**Instructor's original command:**

```bash
podman-compose down
```

**Explicit-file equivalent used with this repository:**

```bash
podman-compose -f podman-compose.yml down
```

Expected: the project containers are stopped/removed and its ordinary project network is removed. Output wording/order may vary. A `down` operation can remove containers and their unmounted writable state: **do not treat this PostgreSQL demo as a durable database**.

### Subtask 4.2 — Verify cleanup

**Instructor's original command:**

```bash
podman ps -a
```

This lists **all** Podman containers for the current user, not only this Compose project. Other course containers may remain, and that alone is **not a cleanup failure**. To check the current project, use:

```bash
podman-compose -f podman-compose.yml ps
```

Don't run global force-removal commands to make `podman ps -a` empty; they can delete unrelated labs.

## 7. Troubleshooting — instructor tips + safer checks

| Symptom | Explanation | Check/fix |
| --- | --- | --- |
| `address already in use` on 8080 | Another process/container publishes host port 8080 | Check `ss -ltnp`; use instructor's alternative `8081:80` and browse port 8081. |
| Nginx returns forbidden/empty content | Wrong `./html` path, empty directory, or SELinux permissions | Run `ls -l html/index.html` and `podman-compose ... logs web`; on RHEL use instructor's `:Z` mount example below. |
| Image pull fails | Network/registry access or image reference | Test connectivity, use explicit `docker.io/library/...` names, inspect error details. |
| `podman-compose` isn't recognized | Not installed or wrong PATH | Check `podman-compose --version`; use an available package/isolated Python environment. |
| Compose file not found | Some tools prefer other default filenames | Pass `-f podman-compose.yml` explicitly. |
| Container names differ | Naming depends on tool/version/project name | Prefer `podman-compose ... exec db` over hard-coded names. |
| DB starts then exits | Startup/init/permission issues | `podman-compose -f podman-compose.yml logs db`. |
| VM browser can't reach URL | VM host vs guest network boundary | Curl from inside VM; configure a secure VM forwarding path if external access is needed. |

**Instructor's SELinux correction snippet:**

```yaml
volumes:
  - ./html:/usr/share/nginx/html:Z
```

The provided repository YAML already uses this mount option. With SELinux, `:Z` privately relabels the host directory for this container; use only on directories intended for this purpose, not broad system paths.

## 8. Lab completion and evidence

- [x] Task 1.1 — Explain Compose structure (learner-confirmed).
- [x] Task 1.2 — Create Compose file (learner-confirmed).
- [x] Task 2.1 — Launch services (learner-confirmed).
- [x] Task 2.2 — Verify running containers (learner-confirmed).
- [x] Task 3.1 — Serve custom HTML (learner-confirmed).
- [x] Task 3.2 — Run PostgreSQL version query (learner-confirmed).
- [x] Task 4.1 — Stop stack (learner-confirmed).
- [x] Task 4.2 — Verify cleanup (learner-confirmed).

**Evidence to retain if available:** screenshot of `podman ps` showing both services and `curl http://localhost:8080` output; optionally a screenshot of `SELECT version()`. Do not upload invented screenshots or label expected output as actual captured execution.

## 9. Quick revision

```bash
# Run from the lab folder containing podman-compose.yml and html/
podman --version
podman-compose --version
podman-compose -f podman-compose.yml up -d
podman ps
curl http://localhost:8080
podman-compose -f podman-compose.yml exec db psql -U postgres -c 'SELECT version();'
podman-compose -f podman-compose.yml down
podman ps -a
```

## 10. Conclusion / next steps

This lab demonstrates **declarative management of multiple containers** with an HTTP-facing Nginx service and an independently testable PostgreSQL service. It introduces YAML-based orchestration and highlights important distinctions between **bind mounts and database persistence**, **container ports and published host ports**, and **service-level vs project-level lifecycle management**.

**Further exploration (not claimed as completed):** add PostgreSQL named-volume storage, configure service-specific networks, use `podman-compose ... config` where supported, connect an actual application service to PostgreSQL, and explore Compose healthchecks and multi-container deployments in Kubernetes/OpenShift.
