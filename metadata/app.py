import os
import json
import io
from datetime import datetime, timezone
from flask import Flask, request, jsonify
from minio import Minio
from minio.error import S3Error

app = Flask(__name__)

client = Minio(
    os.environ["MINIO_ENDPOINT"],
    access_key=os.environ["MINIO_ROOT_USER"],
    secret_key=os.environ["MINIO_ROOT_PASSWORD"],
    secure=False,
)

BUCKET       = os.environ["MINIO_BUCKET"]
META_PREFIX  = "meta_"
META_EXT     = ".json"


def meta_key(original_key):
    return f"{META_PREFIX}{original_key}{META_EXT}"


def ensure_bucket():
    if not client.bucket_exists(BUCKET):
        client.make_bucket(BUCKET)


@app.route("/health")
def health():
    return {"status": "ok"}


@app.route("/metadata", methods=["POST"])
def store_metadata():
    """
    Called after a file is uploaded.
    Expects JSON body: { "key": "uuid.jpg", "original_filename": "photo.jpg",
                         "size": 204800, "content_type": "image/jpeg" }
    """
    data = request.get_json()
    if not data or "key" not in data:
        return jsonify({"error": "missing key in request body"}), 400

    ensure_bucket()

    record = {
        "key":               data["key"],
        "original_filename": data.get("original_filename", "unknown"),
        "size_bytes":        data.get("size", 0),
        "content_type":      data.get("content_type", "application/octet-stream"),
        "uploaded_at":       datetime.now(timezone.utc).isoformat(),
    }

    payload = json.dumps(record).encode("utf-8")
    mk = meta_key(data["key"])

    client.put_object(
        BUCKET,
        mk,
        io.BytesIO(payload),
        length=len(payload),
        content_type="application/json",
    )

    return jsonify({"metadata_key": mk, "record": record}), 201


@app.route("/metadata/<path:key>")
def get_metadata(key):
    mk = meta_key(key)
    try:
        response = client.get_object(BUCKET, mk)
        record = json.loads(response.read().decode("utf-8"))
        return jsonify(record)
    except S3Error as e:
        if e.code in ("NoSuchKey", "NoSuchBucket"):
            return jsonify({"error": "metadata not found"}), 404
        return jsonify({"error": str(e)}), 500


@app.route("/metadata")
def list_metadata():
    try:
        objects = client.list_objects(BUCKET, prefix=META_PREFIX)
        records = []
        for obj in objects:
            try:
                response = client.get_object(BUCKET, obj.object_name)
                record = json.loads(response.read().decode("utf-8"))
                records.append(record)
            except Exception:
                continue
        return jsonify(records)
    except S3Error as e:
        if e.code == "NoSuchBucket":
            return jsonify([])
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5004)