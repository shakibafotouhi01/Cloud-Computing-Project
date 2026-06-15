import os
import io
from flask import Flask, jsonify
from minio import Minio
from minio.error import S3Error
from PIL import Image

app = Flask(__name__)

client = Minio(
    os.environ["MINIO_ENDPOINT"],
    access_key=os.environ["MINIO_ROOT_USER"],
    secret_key=os.environ["MINIO_ROOT_PASSWORD"],
    secure=False,
)

BUCKET      = os.environ["MINIO_BUCKET"]
THUMB_SIZE  = (128, 128)
THUMB_PREFIX = "thumb_"

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp"}


@app.route("/health")
def health():
    return {"status": "ok"}


@app.route("/thumbnail/<path:key>", methods=["POST"])
def generate_thumbnail(key):
    ext = os.path.splitext(key)[1].lower()
    if ext not in IMAGE_EXTENSIONS:
        return jsonify({"error": f"unsupported file type: {ext}"}), 400

    # download original from MinIO
    try:
        response = client.get_object(BUCKET, key)
        original_data = response.read()
    except S3Error as e:
        if e.code in ("NoSuchKey", "NoSuchBucket"):
            return jsonify({"error": "original file not found"}), 404
        return jsonify({"error": str(e)}), 500

    # generate thumbnail with Pillow
    img = Image.open(io.BytesIO(original_data))
    img.thumbnail(THUMB_SIZE)

    # convert back to bytes
    output = io.BytesIO()
    fmt = "JPEG" if ext in (".jpg", ".jpeg") else "PNG"
    img.save(output, format=fmt)
    output.seek(0)
    size = output.getbuffer().nbytes

    # store thumbnail back in MinIO with a "thumb_" prefix
    thumb_key = THUMB_PREFIX + key
    client.put_object(
        BUCKET,
        thumb_key,
        output,
        length=size,
        content_type=f"image/{fmt.lower()}",
    )

    return jsonify({
        "original_key": key,
        "thumbnail_key": thumb_key,
        "thumbnail_size": f"{THUMB_SIZE[0]}x{THUMB_SIZE[1]}",
    }), 201


@app.route("/thumbnails")
def list_thumbnails():
    try:
        objects = client.list_objects(BUCKET, prefix=THUMB_PREFIX)
        thumbs = [
            {
                "key": obj.object_name,
                "size": obj.size,
                "last_modified": str(obj.last_modified),
            }
            for obj in objects
        ]
        return jsonify(thumbs)
    except S3Error as e:
        if e.code == "NoSuchBucket":
            return jsonify([])
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5003)