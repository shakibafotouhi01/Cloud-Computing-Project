# Cloud-Computing-Project — Distributed Data

> **Cloud Computing Technologies 2025/2026 ** · University of Milan · Profs. Anisetti & Ardagna

A distributed file storage system built with **MinIO** (4-node erasure-coded cluster), two **Python/Flask microservices**, and a full **observability stack** (Prometheus + Grafana). Demonstrates fault tolerance, high availability, and access control as required by the project specification.

---

## Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [Services & Ports](#services--ports)
- [API Reference](#api-reference)
- [Fault Tolerance Demo](#fault-tolerance-demo)
- [Monitoring](#monitoring)
- [Security](#security)
- [Non-Functional Properties](#non-functional-properties)
- [Stopping the System](#stopping-the-system)

---

## Architecture

```
                        ┌─────────────────────────────────┐
  you (curl/browser)    │         Docker network           │
         │              │         (minio_net)              │
    ┌────┴─────┐        │                                  │
    │ :5001    │        │   ┌──────────────────────┐       │
    │ uploader ├────────┼──►│   nginx :9000/:9001  │       │
    └──────────┘        │   │   (load balancer)    │       │
    ┌──────────┐        │   └──────┬───────────────┘       │
    │ :5002    │        │          │  round-robin           │
    │  reader  ├────────┼──►       │                        │
    └──────────┘        │   ┌──────▼──┬────────┬────────┐  │
                        │   │ minio1  │ minio2 │ minio3 │  │
                        │   │ minio4  │        │        │  │
                        │   └─────────┴────────┴────────┘  │
                        │        erasure coding EC:2        │
                        │                                   │
                        │   prometheus :9090                │
                        │   grafana    :3000                │
                        └─────────────────────────────────-─┘
```

**4 MinIO nodes** store every file split across data + parity chunks via erasure coding (EC:2). Any 2 nodes can die simultaneously — all files remain readable. nginx load-balances in front of all 4 nodes. The two Flask microservices talk exclusively to nginx, never to individual nodes directly.

---

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Docker Desktop | ≥ 4.x | [docker.com](https://www.docker.com/products/docker-desktop/) |
| Docker Compose | included with Desktop | — |
| bash | any | Git Bash on Windows |

> **Windows users:** make sure Docker Desktop is set to **Linux containers** (right-click the tray icon).

---

## Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/YOUR_USERNAME/project2-distributed-data.git
cd project2-distributed-data
```

### 2. Create the `.env` file

```bash
cp .env.example .env
```

Or create it manually:

```env
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin123
APP_BUCKET=uploads
```

### 3. Start everything

```bash
docker compose up -d --build
```

Wait ~30 seconds for the MinIO cluster to form and health checks to pass.

### 4. Verify all containers are running

```bash
docker compose ps
```

Expected output — all 8 containers `running` or `running (healthy)`:

```
NAME          STATUS              PORTS
minio1        running (healthy)
minio2        running (healthy)
minio3        running (healthy)
minio4        running (healthy)
nginx         running             0.0.0.0:9000->9000, 0.0.0.0:9001->9001
uploader      running             0.0.0.0:5001->5001
reader        running             0.0.0.0:5002->5002
prometheus    running             0.0.0.0:9090->9090
grafana       running             0.0.0.0:3000->3000
```

### 5. Upload your first file

```bash
echo "hello distributed world" > test.txt
curl -X POST http://localhost:5001/upload -F "file=@test.txt"
```

Response:

```json
{"bucket": "uploads", "key": "a3f9c2d1-xxxx.txt"}
```

### 6. Read it back

```bash
curl http://localhost:5002/files
curl http://localhost:5002/files/a3f9c2d1-xxxx.txt
```

---

## Project Structure

```
project2-distributed-data/
├── docker-compose.yml          # all 8 containers, volumes, networks
├── .env                        # secrets (never commit this)
├── .env.example                # template — safe to commit
├── .gitignore
├── demo_fault_tolerance.sh     # automated fault injection demo
│
├── storage/
│   └── nginx.conf              # load balancer config
│
├── uploader/
│   ├── Dockerfile
│   ├── requirements.txt
│   └── app.py                  # POST /upload
│
├── reader/
│   ├── Dockerfile
│   ├── requirements.txt
│   └── app.py                  # GET /files, GET /files/{key}, DELETE /files/{key}
│
└── monitoring/
    ├── prometheus.yml           # scrape config (JWT bearer token)
    └── grafana/
        └── datasource.yml       # auto-provisioned Prometheus datasource
```

---

## Services & Ports

| Service | URL | Credentials |
|---|---|---|
| **Uploader API** | `http://localhost:5001` | — |
| **Reader API** | `http://localhost:5002` | — |
| **MinIO S3 API** | `http://localhost:9000` | `minioadmin` / `minioadmin123` |
| **MinIO Console** | `http://localhost:9001` | `minioadmin` / `minioadmin123` |
| **Prometheus** | `http://localhost:9090` | — |
| **Grafana** | `http://localhost:3000` | `admin` / `admin123` |

---

## API Reference

### Uploader — `http://localhost:5001`

#### `POST /upload`
Upload a file to the distributed storage cluster.

```bash
curl -X POST http://localhost:5001/upload \
  -F "file=@/path/to/your/file.jpg"
```

**Response `201`:**
```json
{
  "key": "550e8400-e29b-41d4-a716-446655440000.jpg",
  "bucket": "uploads"
}
```

#### `GET /health`
```bash
curl http://localhost:5001/health
# {"status": "ok"}
```

---

### Reader — `http://localhost:5002`

#### `GET /files`
List all files in the bucket.

```bash
curl http://localhost:5002/files
```

**Response `200`:**
```json
[
  {
    "key": "550e8400-e29b-41d4-a716-446655440000.jpg",
    "size": 204800,
    "last_modified": "2025-01-01 12:00:00+00:00"
  }
]
```

#### `GET /files/{key}`
Download a file by its key. Streamed in 32 KB chunks — works for large files.

```bash
curl http://localhost:5002/files/550e8400-e29b-41d4-a716-446655440000.jpg \
  --output downloaded.jpg
```

#### `DELETE /files/{key}`
Delete a file.

```bash
curl -X DELETE http://localhost:5002/files/550e8400-e29b-41d4-a716-446655440000.jpg
# HTTP 204 No Content
```

#### `GET /health`
```bash
curl http://localhost:5002/health
# {"status": "ok"}
```

---

## Fault Tolerance Demo

The demo script automates the full fault injection sequence. Run it with all containers up:

```bash
bash demo_fault_tolerance.sh
```

### What it does

| Step | Action | Expected result |
|---|---|---|
| 1 | Upload a test file | HTTP 201 — success |
| 2 | Read with all 4 nodes online | HTTP 200 — content correct |
| 3 | **Kill minio1** | HTTP 200 — erasure coding masks the failure |
| 4 | **Kill minio2** (2 nodes dead) | HTTP 200 — at EC:2 limit, still readable |
| 5 | **Kill minio3** (quorum lost) | HTTP 500 — MinIO refuses (CAP: CP behaviour) |
| 6 | Restart all 3 nodes | HTTP 200 — automatic self-healing in ~15 s |

### Why step 5 fails (and why that's correct)

MinIO is a **CP system** (CAP theorem). With only 1 of 4 nodes alive it cannot guarantee data consistency, so it refuses to serve rather than potentially returning corrupt data. This is the correct, safe behaviour for a storage system.

### Running individual steps manually

```bash
# kill a node
docker compose stop minio1

# prove the file is still there
curl http://localhost:5002/files/<key>

# bring it back
docker compose start minio1
```

---

## Monitoring

### Prometheus

Open `http://localhost:9090/targets` — the `minio-cluster` target should show **UP**.

Useful queries in the Prometheus query box:

```
# number of online MinIO nodes
minio_cluster_nodes_online_total

# total storage used (bytes)
minio_cluster_usage_total_bytes

# objects stored
minio_cluster_objects_count
```

### Grafana

1. Open `http://localhost:3000` — log in with `admin` / `admin123`
2. Go to **Dashboards** → import dashboard ID **`13502`** (official MinIO dashboard)
3. Select **Prometheus** as the data source → **Import**

The dashboard shows live node count, storage utilisation, read/write throughput, and object count. During the fault demo, watch the **Nodes Online** panel drop from 4 → 3 → 2 → 1 → 4 in real time.

---

## Security

### Bucket policy — no anonymous access

The `uploads` bucket is configured to deny all unauthenticated requests:

```bash
# verify
docker exec -it project2-distributed-data-minio1-1 sh
mc alias set local http://nginx:9000 minioadmin minioadmin123
mc anonymous get local/uploads
# Access permission for `local/uploads` is `none`
```

Anonymous requests get **HTTP 403**:

```bash
curl -v http://localhost:9000/uploads/
# < HTTP/1.1 403 Forbidden
```

### Role-based access control

Two users are configured:

| User | Password | Permissions |
|---|---|---|
| `minioadmin` | `minioadmin123` | Full admin — read, write, delete, manage |
| `readeruser` | `readerpassword123` | Read-only — `s3:GetObject`, `s3:ListBucket` |

---

## Non-Functional Properties

| Property | Mechanism | Verified by |
|---|---|---|
| **Fault tolerance** — crash failure | EC:2 erasure coding across 4 nodes | `demo_fault_tolerance.sh` steps 3–4 |
| **Fault tolerance** — omission failure | nginx health checks stop routing to dead nodes | `docker compose ps` health status |
| **High availability** | `restart: always` + nginx round-robin | Container auto-restart on failure |
| **Consistency (CP)** | MinIO refuses requests below quorum | `demo_fault_tolerance.sh` step 5 |
| **Authentication** | `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` required | `curl http://localhost:9000/uploads/` → 403 |
| **Authorisation** | Bucket policy + read-only RBAC user | `mc anonymous get local/uploads` |
| **Observability** | Prometheus metrics + Grafana dashboard | `http://localhost:9090` + `:3000` |

---

## Stopping the System

Stop all containers but **keep your data** (volumes preserved):

```bash
docker compose down
```

Stop everything and **wipe all stored files** (full reset):

```bash
docker compose down -v
```

Restart after stopping:

```bash
docker compose up -d
```

---
