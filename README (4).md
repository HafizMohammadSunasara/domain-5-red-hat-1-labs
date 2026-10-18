# Lab 04 — Creating and Managing Pods

**Status:** Completed (self-reported)  
**Track:** Domain 5 → Linux and Open Source → Red Hat 1

## Purpose

Learn the Podman pod model: grouping containers, sharing networking and explicitly sharing storage.

## Pod and Nginx

```bash
podman pod create --name demo-pod -p 127.0.0.1:8080:80
podman run -d --pod demo-pod --name nginx-container docker.io/library/nginx:alpine
podman pod ps
podman ps --pod
curl http://localhost:8080
```

A Podman pod typically includes an **infra container** that helps maintain shared namespaces.

## Redis sidecar and shared networking

```bash
podman run -d --pod demo-pod --name redis-container docker.io/library/redis:alpine
podman exec redis-container redis-cli ping   # Expect PONG if server is ready
podman pod inspect demo-pod
```

The pod's containers share networking; using the Redis endpoint `127.0.0.1:6379` from another container in the pod is appropriate. Trying `ping redis-container` is not a reliable pod-network verification because DNS names are not necessarily allocated independently within a shared network namespace. Nginx itself does not magically use Redis without configuring an application/client.

## Shared volume concept

Networking and filesystem sharing are separate. For a volume-only demonstration, use utility containers in the pod instead of starting a **second Nginx and second Redis server** on the already occupied ports:

```bash
podman volume create lab04-shared-vol
podman run -d --pod demo-pod --name lab04-writer -v lab04-shared-vol:/data docker.io/library/alpine sleep 3600
podman run -d --pod demo-pod --name lab04-reader -v lab04-shared-vol:/data docker.io/library/alpine sleep 3600
podman exec lab04-writer touch /data/shared-test.txt
podman exec lab04-reader ls -l /data/shared-test.txt
```

The commands above are **recommended illustrative examples**, not verified command logs from the learner's lab session. Confirm container names and volume references before any cleanup.

## Safe cleanup example

```bash
podman pod rm -f demo-pod    # Deletes this named pod and its containers only
podman volume rm lab04-shared-vol
```

The `-f` operation is destructive for this pod; only use it when done and when that pod contains no data to preserve.

## Evidence

Completion confirmed by learner. No terminal transcript or screenshot has been published for Lab 04.
