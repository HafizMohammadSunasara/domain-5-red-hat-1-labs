# Lab 17 — Engineering Deep Dive: Compose Dependencies, Scaling & Service Discovery

**Scope:** Compose startup dependencies; horizontal replicas; Flask/Redis application networking; Podman/Docker differences; reliability and operational debugging.  
**Status:** Lab completed per learner confirmation (**self-reported**). Examples and diagrams are learning references, **not** captured production telemetry or independent tests.  
**Companion:** [Complete Practical Runbook](README.md).

## 1. Why Compose dependencies matter

Multi-container applications are systems of interacting processes, not one giant process. A web application might need a cache, a database or a message broker. The order those processes start can affect early requests.

Consider this model:

```text
         Client / curl
              |
              v
     Flask webapp service       <-- HTTP :5000 published to local host
              |
     Redis protocol/TCP :6379   <-- PRIVATE Compose network
              v
        Redis service
```

Compose gives each service an identity and a shared project network. The Python client uses `redis` as the hostname; it should not need a hardcoded container IP. Container IPs may change when containers are recreated.

Task 1 and Task 2 use **Nginx**, not Flask. They illustrate startup order and scaling. Nginx does **not** automatically connect to or display data from Redis simply because it has `depends_on: [redis]`. Task 3 introduces actual application-level integration.

## 2. What `depends_on` does — and does not do

In the instructor's short form:

```yaml
services:
  webapp:
    depends_on:
      - redis
```

Compose orders service creation/start actions so Redis starts first. However, a started container is not proof that the Redis process has finished initialization, completed recovery, or begun accepting TCP connections. This is a *race condition* at the application boundary.

**Four distinct concepts:**

| Concept | Meaning | What verifies it? |
| --- | --- | --- |
| Container created | Engine has created a container object | `ps -a`, inspect |
| Container running | Main process is currently alive | `ps`, `State.Running` |
| Service ready | Application is prepared to handle useful traffic | Application-specific health/readiness check |
| Dependents healthy | A cross-service request actually succeeds | End-to-end test (Flask request increments Redis key) |

**Why this matters:** A database may take seconds to initialize even after its process has started. Applications should tolerate temporary dependency unavailability.

### Safer readiness approach (where supported)

Docker Compose supports health checks and long-form dependencies:

```yaml
services:
  redis:
    image: docker.io/library/redis:alpine
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 10

  webapp:
    build: .
    depends_on:
      redis:
        condition: service_healthy
```

An extended example is included as [examples/compose-task3-healthchecked.yml](examples/compose-task3-healthchecked.yml). **Provider caveat:** Some Podman Compose versions implement only subsets of Docker Compose health dependencies; verify actual support before relying on long-form `depends_on`.

Even when health checks work, a previously healthy dependency can fail later. Applications still require error handling and sensible retries.

## 3. `depends_on` is not network access control

Dependencies define orchestration order. They do **not** create authorization or firewall isolation and do not configure Nginx as a Redis client.

In the examples, Compose places services on a project network, often named along the lines of `compose-dependencies-lab_default`. The precise name can vary by provider/project settings.

Within that network:

```text
Flask -> redis:6379 -> Redis
```

This uses internal service-to-service networking. **You do not need `-p 6379:6379` to let Flask contact Redis on the same Compose network.** Publishing Redis to the host is a separate exposure and is omitted from Task 3.

To debug name resolution or network membership, inspect the active containers and network using engine commands rather than assuming IP addresses.

## 4. Scaling: replicas versus one container

Task 2 changes the Nginx service from one to three replicas:

```yaml
webapp:
  image: nginx:alpine
  ports:
    - "8080-8082:80"
  depends_on:
    - redis
  deploy:
    replicas: 3
```

And the instructor runs:

```bash
docker-compose up -d --scale webapp=3
```

**Replicas** are independent container instances from the same service definition/image, each with a distinct process and hostname.

```text
                  one Compose service: webapp
                           |
                    three instances
            +--------------+--------------+
            |              |              |
      nginx replica 1 nginx replica 2 nginx replica 3
           :80            :80            :80
            |              |              |
        host port A    host port B    host port C
        (within configured range, if provider supports it)
```

### Why fixed host port causes trouble

A host IP/protocol/port tuple generally cannot be bound by three independent listeners simultaneously. Three containers can **each** listen on port 80 *inside their own network namespace*, but three host mappings like `8080:80` compete for the same host port.

The instructor addresses that with `8080-8082:80`. Verify the provider's port allocation using `ps`. If it doesn't support ranges or conflicts persist, assign ports explicitly in separate test services, use dynamically allocated host ports where appropriate, or front the replicas with a reverse proxy/load balancer.

### Scaling is not automatically load balancing

Having three replicas does not mean one public endpoint (`localhost:8080`) automatically distributes requests among them. With direct host-port mappings, clients may visit distinct ports. Production applications often use a load balancer or service abstraction.

**AWS ECS connection:** Service desired count controls how many tasks run; a load balancer (when configured) can distribute requests.  
**Kubernetes connection:** Deployment replicas create multiple Pods; a Service provides a stable network endpoint.  
Compose gives a local development approximation of the concepts, not the same scheduler or availability guarantees.

### Replicas are not data replicas

Three stateless Nginx instances don't replicate data by themselves. If they depend on session state, external shared storage/cache/database or application design is needed. Redis in this lab is a separate single service and single potential point of failure.

## 5. Why the hostname is `redis`, not `localhost`

Task 3 uses:

```python
redis_host = os.environ.get('REDIS_HOST', 'redis')
redis_client = redis.Redis(host=redis_host, port=6379)
```

Inside the Flask container, `localhost` means **that Flask container**, not the Redis container and not the physical host. The hostname `redis` refers to the **Redis service** via Compose's internal name resolution.

Common mistake:

```python
redis.Redis(host='localhost', port=6379)  # wrong if Redis is in another container
```

The actual container IP is not durable: rebuilds and restarts can change it. A stable service name is easier to maintain and works across many container networking models.

**Task 3 env var:** `REDIS_HOST=redis` overrides the code's default if needed. The root final Compose file uses YAML-map syntax; the instructor uses list syntax. Both express the same basic setting.

## 6. The hit counter: what a test actually proves

The instructor's Flask route performs:

```python
count = redis_client.incr('hits')
return f'Hello World! This page has been viewed {count} times.\n'
```

- `INCR hits` is an atomic Redis increment for the key `hits`.
- If the key does not exist, Redis initializes it as zero before incrementing.
- Repeating an HTTP request produces successive counts **while the Redis state is preserved**.
- A result like `1`, then `2`, demonstrates an HTTP request reaching Flask and a successful Redis request/response; it does **not** establish production reliability, high availability or durable storage.

**Important:** Original Stage 3 has **no Redis volume**; stopping/removing/recreating Redis may discard the counter. Don't confuse database/service connectivity with persistence. Lab 10–12 covered persistent storage and backups separately.

### Why the improved `app.py` differs

The root [app.py](app.py) adds bounded retry/error handling and a `/health` endpoint. These are **optional engineering enhancements** and should not be misrepresented as the instructor's original app. The unchanged original is saved at [examples/app.instructor.py](examples/app.instructor.py).

Its behavior is intentionally still easy to validate: `/` increments a Redis key; `/health` verifies Redis availability. When Redis cannot be reached, it reports an HTTP `503` rather than presenting a normal success page.

## 7. Compose files and Dockerfiles are different layers

- `Dockerfile`: **How to build** the Flask app image (base Python runtime, dependencies, code, default command).
- `docker-compose.yml`: **How to run** the distributed application (two services, build directive, Redis host, port, dependency order, project networking).
- `app.py`: Application logic, HTTP endpoint and Redis client.
- `requirements.txt`: Python dependency contract.

```text
 Dockerfile + app.py + requirements.txt
                   |
                   v
            Flask image
                   |
               Compose
              /       \\
             v         v
       Flask service  Redis service
```

The original instructor Dockerfile installs unbounded `flask redis` dependencies on `python:3.9-alpine`. Python 3.9 is end-of-life as of 2025; the main lab Dockerfile uses a supported Python 3.12 base and bounded package versions for clearer current practice. Original commands and Dockerfile are archived unmodified in the examples directory and README.

**DevSecOps note:** Better deployments also pin exact artifact digests after testing, build images in CI, scan dependencies, and run with least-privileged runtime settings. None of those stronger practices is *demonstrated* merely by this learning lab.

## 8. The three YAML versions — avoid losing work

The instructor asks you to modify **the same** `docker-compose.yml` three times. A GitHub repository should retain all variants:

| Stage | File | Contents | Purpose |
| --- | --- | --- | --- |
| Task 1 | [`examples/compose-task1.yml`](examples/compose-task1.yml) | Redis + Nginx; basic `depends_on` | Startup ordering |
| Task 2 | [`examples/compose-task2-scaling.yml`](examples/compose-task2-scaling.yml) | Redis + Nginx; replicas/range | Scaling |
| Task 3 original | [`examples/compose-task3-instructor.yml`](examples/compose-task3-instructor.yml) | Redis + Flask build | Connectivity |
| Task 3 final | [`docker-compose.yml`](docker-compose.yml) | Redis + Flask; safer local port | Reproducible app |
| Optional advanced | [`examples/compose-task3-healthchecked.yml`](examples/compose-task3-healthchecked.yml) | Redis healthcheck + conditional start | Readiness concept |

Before moving between stages, run a provider-appropriate `down` to avoid conflicting old service containers, then activate the desired stage. Any `cp` overwrites the working `docker-compose.yml`, so keep a pristine copy of the package when experimenting.

## 9. How to troubleshoot systematically

Think of the chain in this order:

```text
HTTP client
  -> published host port
  -> Flask container process
  -> Compose DNS service name "redis"
  -> container-to-container TCP 6379
  -> Redis process readiness
  -> Redis INCR key
  -> Flask HTTP response
```

If a request fails, isolate the broken link.

| Observation | Questions | Practical checks |
| --- | --- | --- |
| `curl: connection refused` on host | Is Flask running? Is host port exposed? | `podman ps`, `podman-compose ps`, `ss -tulnp` |
| Flask HTTP 503 or 500 | Is Redis started and ready? | `podman-compose logs`, Redis `PING`, Compose network |
| DNS lookup fails | Is `REDIS_HOST` exactly the service name `redis`? | Inspect YAML, env, project network |
| Scaling command errors | Does provider support `--scale`? Host port collision? | `podman-compose --help`, `podman ps` |
| Unexpected hit count | Was the counter used already? | Repeat curls, inspect Redis state on disposable environment |
| Unexpected Nginx page at port 5000 | Did you transition to Task 3? Is an old service still bound? | `podman-compose down`, inspect host port/containers |
| Build error | Can Python dependencies install? Is Dockerfile in context? | `podman-compose logs`, rebuild, image build output |
| One service shown after startup | Did sibling image pull/start fail? | `docker compose ps -a`, `podman ps -a`, logs |

### Rootless Podman and SELinux

No source-code bind mount is used in Task 3; `build: .` copies application files into the image. Therefore RHEL's bind-mount `:Z` requirement from previous labs does not apply to this final Flask example. If adding mounts later, consider proper SELinux labeling and rootless user namespace ownership rather than blindly changing permissions with `sudo chown`.

### Operational security

- Use `127.0.0.1:5000:5000` for local practice so Flask isn't automatically exposed to the LAN.
- Don't publish Redis's 6379 port publicly; Stage 3 communicates on the internal project network.
- Never store real production credentials as plaintext in a public repository. This lab uses no passwords because Redis is a disposable local demonstration.
- Don't trust a passing `curl` as comprehensive functional/security testing.
- Don't deploy Flask's built-in development server as a production web server; use a suitable WSGI deployment approach.

## 10. Interview questions — answer in your own words

1. **What problem does Compose solve?** It describes and manages multi-service container applications from declarative YAML rather than repeated manual runtime commands.
2. **What does `depends_on` guarantee?** Dependency start/stop ordering under relevant Compose behavior; the simple form does not wait for application-level readiness.
3. **How can you check Redis readiness?** An application-aware test such as `redis-cli ping`, possibly a healthcheck and retry handling.
4. **Why not use `localhost` for Redis from Flask?** Because localhost points to the Flask container's own network namespace.
5. **How does service discovery work?** Services on the same Compose network can typically resolve each other by service name.
6. **Why does `webapp` require a build in Task 3?** It is a custom Flask app, unlike Tasks 1/2 which use a prebuilt Nginx image.
7. **What does `-d` change?** Compose starts services without attaching the current terminal to their output.
8. **What is a replica?** A separate instance of a service with its own container process/environment.
9. **Why can't three replicas use `8080:80` on the same host IP?** The fixed host port would be contested by multiple bindings.
10. **Does `8080-8082:80` itself provide a load balancer?** No. It permits distinct published ports where supported; a single balanced endpoint is separate.
11. **Does scaling guarantee availability?** No; replicas can share single points of failure and require monitoring and routing.
12. **What is the role of `deploy.replicas` versus `--scale`?** Declarative desired count versus explicit CLI scale request; actual support varies by provider.
13. **How do you verify all three different hostnames?** Inspect individual containers or use Compose replica index support rather than one default `exec`.
14. **What does Redis `INCR` provide?** Atomic increment of a numeric key, useful for the sample hit counter.
15. **Will the hit count always start at 1?** Only when the underlying key is absent; earlier state/requests can change it.
16. **Does Task 3 prove persistent storage?** No; the instructor configuration doesn't declare a Redis data volume.
17. **What is `docker-compose down` for?** Project-scoped stop/removal of Compose services and network; it normally does not delete named volumes without additional flags.
18. **How is this related to ECS/Kubernetes?** Similar concepts (service dependency, replicas, discovery), but production orchestration has different scheduling, networking, rollout and health primitives.
19. **Why separate Compose, Dockerfile and app logic?** They have different concerns: how to build, how to deploy, what the app does.
20. **Why avoid publishing Redis for Task 3?** Inter-service network access doesn't require exposing the database/cache port to the host or internet.
21. **Why use `/health`?** It provides a health signal independent of incrementing the page counter, although an application-aware check still needs sensible scope/timeouts.
22. **What remains unverified from GitHub documents alone?** Actual screenshots/logs, passing local Compose tests, environment-dependent scaling behavior, and correctness under load.

## 11. Production-grade next steps (not claimed completed)

1. Replace Flask development server with a production WSGI server.
2. Add integration tests and CI builds for the Flask/Redis interaction.
3. Add health checks, resource limits, restart policies and secure secrets management.
4. Make Redis persistent or explicitly disposable based on product requirements; back up state if durability is needed.
5. Add a reverse proxy/load balancer and instrument request/error/latency metrics.
6. Reproduce a Redis outage deliberately and validate how Flask behaves before and after recovery.

**Bottom line:** The key engineering skill in Lab 17 is understanding the difference between **startup ordering**, **service readiness**, **replica count** and **real application connectivity**—four separate things that are easy to confuse when commands seem successful.
