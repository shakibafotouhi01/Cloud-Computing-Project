import os
from flask import Flask, jsonify, Response, stream_with_context
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


@app.route("/health")
def health():
    return {"status": "ok"}


@app.route("/files")
def list_files():
    try:
        objects = client.list_objects(BUCKET)
        files = [
            {"key": obj.object_name, "size": obj.size, "last_modified": str(obj.last_modified)}
            for obj in objects
        ]
        return jsonify(files)
    except S3Error as e:
        if e.code == "NoSuchBucket":
            return jsonify([])
        return jsonify({"error": str(e)}), 500


@app.route("/files/<path:key>")
def download(key):
    try:
        obj = client.get_object(BUCKET, key)
        content_type = obj.headers.get("Content-Type", "application/octet-stream")

        def generate():
            for chunk in obj.stream(32 * 1024):
                yield chunk

        return Response(
            stream_with_context(generate()),
            content_type=content_type,
            headers={"Content-Disposition": f'attachment; filename="{key}"'},
        )
    except S3Error as e:
        if e.code in ("NoSuchKey", "NoSuchBucket"):
            return jsonify({"error": "not found"}), 404
        return jsonify({"error": str(e)}), 500


@app.route("/files/<path:key>", methods=["DELETE"])
def delete(key):
    try:
        client.remove_object(BUCKET, key)
        return "", 204
    except S3Error as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5002)
