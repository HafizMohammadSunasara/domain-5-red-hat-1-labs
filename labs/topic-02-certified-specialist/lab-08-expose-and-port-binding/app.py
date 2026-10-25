"""Tiny teaching-only Flask application for EXPOSE/port publishing experiments."""
from flask import Flask

app = Flask(__name__)


@app.get("/")
def hello():
    return "Hello from the exposed container port!\n", 200, {"Content-Type": "text/plain; charset=utf-8"}


if __name__ == "__main__":
    # Listen on container interfaces, not only the loopback interface.
    # Flask's development server is for the lab, NOT a production HTTP server.
    app.run(host="0.0.0.0", port=8080)
