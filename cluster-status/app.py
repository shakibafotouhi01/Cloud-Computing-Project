import os
import urllib.request
import urllib.error
import json
from flask import Flask, jsonify
from minio import Minio
from minio.error import S3Error

app = Flask(__name__)

client = Minio(
    os.environ["MINIO_ENDPOINT"],
    access_key=os.environ["MINIO_ROOT_USER"],
    secret_key=os.environ["MINIO_ROOT_PASSWORD"],
    secure=False,
)

BUCKET = os.environ["MINIO_BUCKET"]

# individual node addresses for per-node health probing
MINIO_NODES = [
    "http://minio1:9000",
    "http://minio2:9000",
    "http://minio3:9000",
    "http://minio4:9000",
]


def probe_node(url):
    """Returns True if the node responds to its health endpoint."""
    try:
        req = urllib.request.urlopen(
            f"{url}/minio/health/live", timeout=2
        )
        return req.status == 200
    except Exception:
        return False


@app.route("/health")
def health():
    return {"status": "ok"}


@app.route("/cluster/status")
def cluster_status():
    # probe each node individually
    node_statuses = []
    online_count = 0
    for node_url in MINIO_NODES:
        name = node_url.split("//")[1].split(":")[0]   # e.g. "minio1"
        alive = probe_node(node_url)
        if alive:
            online_count += 1
        node_statuses.append({
            "node":   name,
            "url":    node_url,
            "status": "online" if alive else "offline",
        })

    # get storage and object stats from the cluster
    total_bytes  = 0
    object_count = 0
    bucket_exists = False
    try:
        if client.bucket_exists(BUCKET):
            bucket_exists = True
            objects = list(client.list_objects(BUCKET))
            object_count = len(objects)
            total_bytes  = sum(o.size for o in objects if o.size)
    except S3Error:
        pass

    quorum_ok = online_count >= 3   # MinIO needs 3/4 for read quorum

    return jsonify({
        "cluster": {
            "nodes_total":   len(MINIO_NODES),
            "nodes_online":  online_count,
            "nodes_offline": len(MINIO_NODES) - online_count,
            "quorum":        "ok" if quorum_ok else "LOST",
            "ec_config":     "EC:2 (2 data + 2 parity)",
            "can_tolerate":  max(0, online_count - 2),
        },
        "storage": {
            "bucket":        BUCKET,
            "bucket_exists": bucket_exists,
            "objects":       object_count,
            "used_bytes":    total_bytes,
            "used_mb":       round(total_bytes / (1024 * 1024), 2),
        },
        "nodes": node_statuses,
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5005)