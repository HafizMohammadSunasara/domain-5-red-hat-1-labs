"""Lab 17 Flask + Redis page counter, with bounded startup error handling.

Companion to the instructor's original code archived under examples/.
This sample is for local development / lab demonstration, not production.
"""

import os
import time

import redis
from flask import Flask

app = Flask(__name__)
redis_host = os.environ.get("REDIS_HOST", "redis")
redis_client = redis.Redis(
    host=redis_host,
    port=6379,
    socket_connect_timeout=2,
    socket_timeout=2,
)


@app.get("/")
def hello():
    for attempt in range(3):
        try:
            count = redis_client.incr("hits")
            return f"Hello World! This page has been viewed {count} times.\n"
        except redis.exceptions.RedisError:
            if attempt < 2:
                time.sleep(1)
    return "Redis temporarily unavailable. Please retry.\n", 503


@app.get("/health")
def health():
    try:
        redis_client.ping()
        return "OK\n", 200
    except redis.exceptions.RedisError:
        return "Redis unavailable\n", 503


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
