import os
import uuid
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

BUCKET = os.environ["MINIO_BUCKET"]


def ensure_bucket():
    if not client.bucket_exists(BUCKET):
        client.make_bucket(BUCKET)


@app.route("/health")
def health():
    return {"status": "ok"}


@app.route("/upload", methods=["POST"])
def upload():
    if "file" not in request.files:
        return jsonify({"error": "no file field in request"}), 400

    f = request.files["file"]
    if f.filename == "":
        return jsonify({"error": "empty filename"}), 400

    ensure_bucket()

    ext = os.path.splitext(f.filename)[1]
    object_name = f"{uuid.uuid4()}{ext}"
    size = f.seek(0, 2)
    f.seek(0)
    size = f.content_length or -1

    client.put_object(
        BUCKET,
        object_name,
        f.stream,
        length=size,
        part_size=10 * 1024 * 1024,
        content_type=f.content_type or "application/octet-stream",
    )

    return jsonify({"key": object_name, "bucket": BUCKET}), 201


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001)
