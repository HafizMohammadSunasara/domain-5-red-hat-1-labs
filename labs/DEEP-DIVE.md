# Lab 16 — Deep Dive: Podman Compose, Multi-Container Architecture & Networking

> **Engineering companion to** [Lab 16 practical README](README.md). This guide explains why each step works, how it maps to real DevOps workflows, and which details should *not* be mistaken for evidence of production-grade deployment. The learner reports completing the course lab; the examples here are explanations, **not captured run logs**.

## 1. The problem: multiple services, one repeatable definition

A modern application usually contains multiple components: front-end or reverse-proxy, application API, database, cache, queue, etc. Running them manually involves remembering many flags for image, port, environment, mounts, and networks. Inconsistency makes troubleshooting and onboarding difficult.

**Podman Compose solves the local orchestration problem:** describe the desired services in one Compose YAML, then bring them up/down through a common interface. The Compose provider translates that definition into container, network and volume operations. Unlike Kubernetes, it is not itself a cluster scheduler and does not provide multi-node rescheduling, advanced rollout controllers, or production HA out of the box.

```text
                    podman-compose.yml
                  /                    \
                 /     up -d            \
          web service                 db service
          nginx:alpine               postgres:13
          listens :80                listens :5432
          host 8080 → :80            no host port published
             |                            |
     host folder ./html           database container storage
         bind mount               NO explicit volume in course YAML
```

**Crucial limitation:** These services share a *deployment configuration* but are **not connected at the application layer**: serving a static HTML page does not make Nginx query PostgreSQL. To build a real dynamic website, add an application service that knows how to communicate with the database.

## 2. Compose YAML — line by line

The instructor's original YAML is:

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

- **`version: '3.8'`**: the course uses this legacy field; current Compose implementations may warn that it is obsolete. The important semantics are the service declarations.
- **`services`**: logical components in the same project, not necessarily literal service names in every runtime's generated container name.
- **`web` / `db`**: names used by Compose to reference the two services.
- **`image`**: pull and run an image; there is no `build:` section, thus this lab requires **no `Dockerfile` or `Containerfile`**.
- **`ports: ["8080:80"]`**: host-side port 8080 is forwarded to Nginx's port 80. The left side is outside the container; the right side is where Nginx listens.
- **`volumes: ["./html:/usr/share/nginx/html"]`**: maps the project-relative host directory to the Nginx document root. This is a **bind mount**, not a named volume.
- **`environment`**: passes `POSTGRES_PASSWORD` for database image initialization, not a secure production secrets mechanism.

For RHEL, this repository's actual [podman-compose.yml](podman-compose.yml) uses `127.0.0.1:8080:80` to avoid unintended network exposure and `:Z` to accommodate SELinux; its overall two-service functionality remains the same. Docker Hub official images are spelled explicitly as `docker.io/library/...`.

**YAML formatting pitfall:** indentation must use spaces, not tabs. Strings that contain colons (like port mappings) should remain quoted. `services` is a map; `ports` and `volumes` are lists.

## 3. `podman-compose` versus `podman compose`

These look similar but are conceptually different:

- **`podman-compose up -d`** invokes an installed external project called Podman Compose.
- **`podman compose up -d`** uses Podman's thin wrapper to call whichever external Compose provider is configured/installed.
- **`podman run ...`** creates one container directly from CLI options; Compose makes multiple containers reproducible together.

Both Compose implementations can vary in command support, resource naming, default filename detection and exact log messages. To run **this particular repository file** reliably, use:

```bash
podman-compose -f podman-compose.yml up -d
podman-compose -f podman-compose.yml ps
podman-compose -f podman-compose.yml down
```

It is a mistake to assume every Compose provider always discovers `podman-compose.yml` automatically. Standard Compose implementations typically recognize `compose.yaml` and `docker-compose.yml`, but the course deliberately names its file `podman-compose.yml`: `-f` makes the selected file unambiguous.

## 4. Why `html/index.html` belongs in version control

The compose configuration references the host's `./html` directory, so a code reviewer should be able to retrieve both the YAML and the content it mounts:

```text
lab-16-multi-container-applications-with-podman-compose/
├── README.md
├── DEEP-DIVE.md
├── podman-compose.yml
└── html/
    └── index.html
```

The file is the minimal reproducible application content:

```html
<h1>Hello from Podman Compose!</h1>
```

When someone runs `podman-compose ... up -d` from that directory, Nginx reads `/usr/share/nginx/html/index.html`, which points to the host file through a bind mount. Editing and saving the host HTML affects the file that Nginx serves; in this static example, a new HTTP request should see the changed content. This does **not** mean all web frameworks automatically reload source code: processes may cache code or need explicit restart/watchers.

**Sequence detail:** The instructor creates the HTML directory *after* starting the stack. For consistent first-run behavior, make the directory and file **before** `up` as shown in the practical guide. This is a safe ordering improvement, not a missing exercise.

## 5. Networking: what `8080:80` actually does

Consider two separate perspectives:

**Application listener:** Nginx listens on TCP port 80 in its container networking context.

**Host publishing:** Podman forwards a host port to the container listener so a client on the appropriate host interface can reach it.

```text
RHEL host curl http://localhost:8080
                 │
                 ▼
       published host TCP 8080
                 │
                 ▼
       Nginx container TCP 80
                 │
                 ▼
       /usr/share/nginx/html/index.html
```

The instructor's `"8080:80"` may publish on all host interfaces (`0.0.0.0`) depending on environment. For a training demo where remote access is unnecessary, `"127.0.0.1:8080:80"` reduces attack surface.

**VirtualBox warning:** `localhost` means *this machine/network namespace*. `curl localhost:8080` in RHEL VM is a test of RHEL's loopback, not Windows laptop loopback. Windows browser access is a separate host↔VM networking issue: NAT forwarding, host-only network, or other controlled path may be required. Never open unnecessary database/debug ports publicly just to make access easier.

### Internal service networks ≠ published host ports

PostgreSQL listens on 5432 inside its runtime network. The YAML does not have `ports` for `db`, so it cannot be assumed reachable through `localhost:5432` on the RHEL host. Compose may make services reachable to each other by service name on a project network, depending on provider/network mode, but a separate *application client* is required to use that database. `nginx:alpine` alone does not become such a client.

## 6. The storage lesson: no database durability guarantee

The YAML includes one mount, **for Nginx HTML**:

```yaml
volumes:
  - ./html:/usr/share/nginx/html
```

It does **not** declare a volume for `/var/lib/postgresql/data`. Even if the container works, removing/recreating it can lose its initialized database state. Some image/runtime combinations involve anonymous storage due to image volume declarations, but **neither durable reuse nor successful restoration is established by this lab**. A named volume makes the requirement explicit.

**Optional extension only (NOT the instructor's completed scope):**

```yaml
services:
  db:
    image: docker.io/library/postgres:13
    environment:
      POSTGRES_PASSWORD: example
    volumes:
      - db_data:/var/lib/postgresql/data

volumes:
  db_data:
```

This is a *different file design* for persistence practice and should not be presented as the original course YAML. Moreover, a persistent volume is **not** a backup: host loss, corruption, operator error, or schema mistakes still require backups, recovery procedures, and restore testing. The instructor's sample output mentioning a `compose-lab_db_data` volume is inconsistent with their actual compose file; no top-level `volumes:` block or database mount exists in the provided YAML.

## 7. Understanding `POSTGRES_PASSWORD`

The official PostgreSQL container initializes its data directory on first startup and needs an appropriate authentication configuration. In a fresh training environment, `POSTGRES_PASSWORD: example` supplies a development password. For an existing initialized database/data volume, editing that environment variable **does not automatically rotate an existing PostgreSQL user's password**.

For production, never hard-code real credentials in a public GitHub repo. Use a controlled secret-management mechanism, restrict network exposure and file access, prefer supported image versions, and implement monitoring/backup policies. PostgreSQL `13` is used here to match the instructor's lab, not because it is a sensible modern production default.

## 8. Project lifecycle and operational commands

### `up -d`

Reconcile the declared Compose project: obtain required images, create resources as needed, and start services detached. `-d` controls terminal attachment, **not** service availability. Postgres might be initializing after container startup.

### `podman ps`

Shows running containers for the current Podman user. It does **not** guarantee applications inside are healthy. Use application probes to verify functionality:

```bash
curl http://localhost:8080
podman-compose -f podman-compose.yml exec db psql -U postgres -c 'SELECT version();'
```

### `podman-compose ... down`

Stops and removes Compose project containers/network. It doesn't mean your entire Podman host becomes empty, so `podman ps -a` might still show other lab containers. Removing containers is different from deleting a separately configured named volume, and flags such as `-v` can alter volume handling: carefully review the actual command before deleting stateful data.

### PostgreSQL access

The course command:

```bash
podman exec -it compose-lab_db_1 psql -U postgres
```

assumes a particular generated container name. Some provider versions produce different names. Using service identity is more stable:

```bash
podman-compose -f podman-compose.yml exec db psql -U postgres
```

Inside `psql`:

```sql
SELECT version();
\q
```

`SELECT version()` shows the server's actual version/build string, and `\q` exits. Merely seeing the container running without executing SQL is weaker verification.

## 9. Failure-first troubleshooting workflow

An engineering review should ask **which layer failed** rather than restarting everything:

| Layer | Typical failure | Diagnostic reasoning |
| --- | --- | --- |
| Tooling | `podman-compose: command not found` | Verify installation, environment, executable PATH; check `podman-compose --version`. |
| Configuration | YAML parser error | Inspect indentation, quoting, filename; validate via provider config command if supported. |
| Image | Registry pull error | Identify repository/tag, connectivity, rate limits and credentials. |
| Container startup | DB exits, app returns 500 | Compare `podman ps -a` against Compose logs; inspect root cause before redeploy. |
| Host port | `bind: address already in use` | Check `ss -ltnp`; change mapping to course suggestion `8081:80` if appropriate. |
| Bind mount | Forbidden/empty Nginx response | Verify `html/index.html`, relative project directory, volume target and SELinux `:Z`. |
| Database | Can't connect to `psql` | Check service running, initialization logs and actual service name. |
| VM connectivity | Windows browser cannot connect | Confirm from inside RHEL VM first, then review VM forwarding/firewall. |
| Cleanup | `podman ps -a` still lists containers | Identify whether those are *unrelated labs* before removing them. |

Useful investigation sequence:

```bash
podman-compose -f podman-compose.yml ps
podman-compose -f podman-compose.yml logs web
podman-compose -f podman-compose.yml logs db
podman ps -a
ss -ltnp | grep 8080
ls -l html/index.html
curl -v http://localhost:8080
```

Don't run `podman rm -f $(podman ps -aq)` to clean one Compose demo: this can destroy unrelated course resources.

### SELinux `:Z` and `:z`

SELinux labeling adds a policy layer beyond Unix filesystem permissions. `:Z` is a **private** mount relabel for one container; `:z` is shared relabeling for use by multiple containers when appropriate. Relabel only the intended project directory. If two containers need to share a host bind path, applying private labeling from different containers can cause access conflicts. Rootless UID/GID mappings introduce a separate ownership dimension—don't blindly `chown` the host directory to a guessed container UID.

## 10. Interview / engineering review questions (with short answers)

1. **What is Podman Compose?** A provider that interprets a Compose YAML into Podman-managed containers and related resources.
2. **Why Compose instead of two `podman run` commands?** Reproducible declaration and joint lifecycle management.
3. **Does `up -d` guarantee DB readiness?** No. Container start isn't the same as application readiness.
4. **What is a Compose service?** A declared logical containerized component (or component configuration).
5. **Explain `8080:80`.** Host port 8080 forwards to container port 80.
6. **What's the benefit of `127.0.0.1:8080:80`?** Avoid exposing the site on all host interfaces by default.
7. **Is `./html` a named volume?** No. It's a bind mount of a host-relative directory.
8. **Does this YAML persist PostgreSQL data?** Not explicitly; no data volume is declared/mounted for `db`.
9. **Why does an example mention `db_data` when YAML does not?** Example output is inconsistent with the given spec; expected resources follow declarations.
10. **Can Nginx automatically query PostgreSQL here?** No; it serves static HTML and no DB-aware application was supplied.
11. **Why `:Z` on RHEL?** To set an appropriate private SELinux label for the mounted directory.
12. **What happens if host port 8080 is busy?** Container may fail to publish; select another free host port such as 8081.
13. **Why not hard-code `compose-lab_db_1`?** Resource names may differ by Compose implementation and version.
14. **What's more robust than that container name?** `podman-compose -f podman-compose.yml exec db ...` references the declared service.
15. **Why is `postgres:13` unsuitable as a long-term default?** It's used to match the curriculum; production requires supported/patched versions and testing.
16. **Why is `POSTGRES_PASSWORD: example` insecure?** It is a hard-coded, public example secret, not a managed production credential.
17. **Why can `podman ps -a` still show containers after `down`?** It includes unrelated containers owned by the same user.
18. **Is a database volume the same as a backup?** No; backup/restore provides separate recovery against storage loss/corruption.
19. **How does source mounting affect Nginx?** Mounted static HTML can be re-served after file edits without rebuilding the image.
20. **What next after Compose?** Add an app↔database service connection, health checks, real persistence, and safe deployment/monitoring workflows.

## 11. Production and portfolio integrity

This is an **educational single-machine multi-container lab**, not a production deployment. It proves understanding of YAML-defined services, mounted Nginx HTML, basic PostgreSQL connectivity and project lifecycle per the learner's own completion report. It does **not** demonstrate production HA, database backup, connection pooling, autoscaling, secret management, full integration or CI/CD unless those are added and tested separately.

For review, keep the real YAML and HTML committed, record only genuine execution evidence, and avoid asserting that the instructor's illustrative output is an actual log. For a separate portfolio-grade project, build a real API connected to PostgreSQL, use named volumes, health checks, environment-specific configuration, least privilege and CI tests.

**Back to:** [Lab 16 practical README](README.md) · [Lab index](../LABS-INDEX.md)
