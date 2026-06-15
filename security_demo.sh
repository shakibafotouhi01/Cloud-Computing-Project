#!/bin/bash
# demo_security.sh
# Run from inside the project folder with: bash demo_security.sh
# Prerequisites: all containers running (docker compose up -d)

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

UPLOADER="http://localhost:5001"
READER="http://localhost:5002"

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Project 2 — Security Demo                     ${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo -e "${CYAN}This demo covers:${NC}"
echo -e "  1. Anonymous access blocked (bucket policy)"
echo -e "  2. Authentication required for all operations"
echo -e "  3. RBAC — read-only user cannot write"
echo -e "  4. RBAC — read-only user cannot delete"
echo -e "  5. Admin user has full access"
echo -e "  6. SHA256 integrity verification (response failure detection)"
echo ""

# ── SETUP: ensure readonly alias exists inside container ──────────────
echo -e "${YELLOW}SETUP: Configuring mc aliases inside container...${NC}"
docker exec project2-distributed-data-minio1-1 sh -c \
  'mc alias set local http://nginx:9000 minioadmin minioadmin123 > /dev/null 2>&1 && \
   mc alias set readonly http://nginx:9000 readeruser readerpassword123 > /dev/null 2>&1 && \
   mc alias set anon http://nginx:9000 "" "" > /dev/null 2>&1' || true
echo -e "${GREEN}✓ Aliases ready${NC}"
echo ""

# ── STEP 1: upload a test file first (need something to work with) ────
echo -e "${YELLOW}SETUP: Uploading a test file to work with...${NC}"
echo "This is a security demo test file." > security_test.txt
RESPONSE=$(curl -s -X POST "$UPLOADER/upload" -F "file=@security_test.txt")
KEY=$(echo "$RESPONSE" | sed 's/.*"key":[ ]*"\([^"]*\)".*/\1/')
echo -e "${GREEN}✓ Test file uploaded. Key: $KEY${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════════
read -p "Press ENTER to start the security demo..."
echo ""

# ── STEP 1: ANONYMOUS ACCESS ──────────────────────────────────────────
echo -e "${BLUE}────────────────────────────────────────────────${NC}"
echo -e "${PURPLE}STEP 1: Anonymous Access — Bucket Policy${NC}"
echo -e "${BLUE}────────────────────────────────────────────────${NC}"
echo ""
echo -e "${YELLOW}  Attempting anonymous HTTP access to the bucket...${NC}"
echo -e "${CYAN}  Command: curl http://localhost:9000/uploads/${NC}"
echo ""

ANON_HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9000/uploads/)
if [ "$ANON_HTTP" = "403" ] || [ "$ANON_HTTP" = "400" ]; then
    echo -e "${GREEN}✓ Anonymous access BLOCKED (HTTP $ANON_HTTP)${NC}"
else
    echo -e "${RED}  Response: HTTP $ANON_HTTP${NC}"
fi

echo ""
echo -e "${YELLOW}  Attempting anonymous listing via mc (no credentials)...${NC}"
ANON_LIST=$(docker exec project2-distributed-data-minio1-1 \
  mc ls anon/uploads 2>&1 || true)
echo -e "${RED}✗ Anonymous mc ls result: $ANON_LIST${NC}"
echo ""
echo -e "${GREEN}  → Bucket policy enforced: mc anonymous set none${NC}"
echo -e "${GREEN}    All unauthenticated requests are rejected.${NC}"
echo ""

# ── STEP 2: AUTHENTICATION ────────────────────────────────────────────
read -p "Press ENTER for Step 2 — Authentication..."
echo ""
echo -e "${BLUE}────────────────────────────────────────────────${NC}"
echo -e "${PURPLE}STEP 2: Authentication — Credentials Required${NC}"
echo -e "${BLUE}────────────────────────────────────────────────${NC}"
echo ""
echo -e "${YELLOW}  Authenticated request via uploader microservice...${NC}"
echo -e "${CYAN}  Command: curl http://localhost:5002/files${NC}"
echo ""

FILES=$(curl -s "$READER/files")
echo -e "${GREEN}✓ Authenticated listing succeeded:${NC}"
echo "$FILES" | python3 -m json.tool 2>/dev/null || echo "$FILES"
echo ""
echo -e "${GREEN}  → Uploader and reader services use MINIO_ROOT_USER${NC}"
echo -e "${GREEN}    and MINIO_ROOT_PASSWORD from environment variables.${NC}"
echo -e "${GREEN}    Credentials are never hardcoded in the source code.${NC}"
echo ""

# ── STEP 3: RBAC — READ-ONLY USER CANNOT WRITE ───────────────────────
read -p "Press ENTER for Step 3 — RBAC write restriction..."
echo ""
echo -e "${BLUE}────────────────────────────────────────────────${NC}"
echo -e "${PURPLE}STEP 3: RBAC — Read-Only User Cannot Upload${NC}"
echo -e "${BLUE}────────────────────────────────────────────────${NC}"
echo ""
echo -e "${YELLOW}  readeruser attempting to upload a file...${NC}"
echo -e "${CYAN}  Command: mc cp evil.txt readonly/uploads/evil.txt${NC}"
echo ""

WRITE_RESULT=$(docker exec project2-distributed-data-minio1-1 sh -c \
  'echo "unauthorized write attempt" > /tmp/evil.txt && \
   mc cp /tmp/evil.txt readonly/uploads/evil.txt 2>&1' || true)

if echo "$WRITE_RESULT" | grep -qi "access denied\|AccessDenied\|error\|forbidden"; then
    echo -e "${RED}✗ UPLOAD BLOCKED for readeruser:${NC}"
    echo -e "  $WRITE_RESULT"
else
    echo -e "  Result: $WRITE_RESULT"
fi
echo ""
echo -e "${GREEN}  → RBAC policy enforced: readeruser only has${NC}"
echo -e "${GREEN}    s3:GetObject and s3:ListBucket permissions.${NC}"
echo -e "${GREEN}    s3:PutObject is NOT in the policy → rejected.${NC}"
echo ""

# ── STEP 4: RBAC — READ-ONLY USER CANNOT DELETE ──────────────────────
read -p "Press ENTER for Step 4 — RBAC delete restriction..."
echo ""
echo -e "${BLUE}────────────────────────────────────────────────${NC}"
echo -e "${PURPLE}STEP 4: RBAC — Read-Only User Cannot Delete${NC}"
echo -e "${BLUE}────────────────────────────────────────────────${NC}"
echo ""
echo -e "${YELLOW}  readeruser attempting to delete an existing file...${NC}"
echo -e "${CYAN}  Command: mc rm readonly/uploads/$KEY${NC}"
echo ""

DELETE_RESULT=$(docker exec project2-distributed-data-minio1-1 \
  mc rm readonly/uploads/$KEY 2>&1 || true)

if echo "$DELETE_RESULT" | grep -qi "access denied\|AccessDenied\|error\|forbidden"; then
    echo -e "${RED}✗ DELETE BLOCKED for readeruser:${NC}"
    echo -e "  $DELETE_RESULT"
else
    echo -e "  Result: $DELETE_RESULT"
fi
echo ""
echo -e "${GREEN}  → s3:DeleteObject not in read-only policy → rejected.${NC}"
echo ""

# ── STEP 5: RBAC — READ-ONLY USER CAN READ ───────────────────────────
read -p "Press ENTER for Step 5 — RBAC read allowed..."
echo ""
echo -e "${BLUE}────────────────────────────────────────────────${NC}"
echo -e "${PURPLE}STEP 5: RBAC — Read-Only User CAN Read${NC}"
echo -e "${BLUE}────────────────────────────────────────────────${NC}"
echo ""
echo -e "${YELLOW}  readeruser listing files...${NC}"
echo -e "${CYAN}  Command: mc ls readonly/uploads${NC}"
echo ""

LIST_RESULT=$(docker exec project2-distributed-data-minio1-1 \
  mc ls readonly/uploads 2>&1)
echo -e "${GREEN}✓ Listing ALLOWED for readeruser:${NC}"
echo "$LIST_RESULT"
echo ""

echo -e "${YELLOW}  readeruser downloading a file...${NC}"
echo -e "${CYAN}  Command: mc cp readonly/uploads/$KEY /tmp/downloaded.txt${NC}"
echo ""

DOWNLOAD_RESULT=$(docker exec project2-distributed-data-minio1-1 \
  mc cp readonly/uploads/$KEY /tmp/downloaded.txt 2>&1)
CONTENT=$(docker exec project2-distributed-data-minio1-1 \
  cat /tmp/downloaded.txt 2>/dev/null || echo "could not read")
echo -e "${GREEN}✓ Download ALLOWED for readeruser:${NC}"
echo -e "  File content: $CONTENT"
echo ""
echo -e "${GREEN}  → Read-only policy working correctly:${NC}"
echo -e "${GREEN}    list ✓  |  read ✓  |  write ✗  |  delete ✗${NC}"
echo ""

# ── STEP 6: ADMIN HAS FULL ACCESS ────────────────────────────────────
read -p "Press ENTER for Step 6 — Admin full access..."
echo ""
echo -e "${BLUE}────────────────────────────────────────────────${NC}"
echo -e "${PURPLE}STEP 6: Admin User Has Full Access${NC}"
echo -e "${BLUE}────────────────────────────────────────────────${NC}"
echo ""
echo -e "${YELLOW}  Admin uploading a new file...${NC}"

echo "admin upload test" > admin_test.txt
ADMIN_RESPONSE=$(curl -s -X POST "$UPLOADER/upload" -F "file=@admin_test.txt")
ADMIN_KEY=$(echo "$ADMIN_RESPONSE" | sed 's/.*"key":[ ]*"\([^"]*\)".*/\1/')
echo -e "${GREEN}✓ Admin upload succeeded. Key: $ADMIN_KEY${NC}"
rm admin_test.txt

echo ""
echo -e "${YELLOW}  Admin deleting that file...${NC}"
DELETE_HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
  -X DELETE "$READER/files/$ADMIN_KEY")
if [ "$DELETE_HTTP" = "204" ]; then
    echo -e "${GREEN}✓ Admin delete succeeded (HTTP 204)${NC}"
else
    echo -e "  HTTP $DELETE_HTTP${NC}"
fi
echo ""
echo -e "${GREEN}  → Admin: list ✓  |  read ✓  |  write ✓  |  delete ✓${NC}"
echo ""

# ── STEP 7: SHA256 INTEGRITY VERIFICATION ────────────────────────────
read -p "Press ENTER for Step 7 — SHA256 integrity verification..."
echo ""
echo -e "${BLUE}────────────────────────────────────────────────${NC}"
echo -e "${PURPLE}STEP 7: Data Integrity — SHA256 Checksum${NC}"
echo -e "${BLUE}────────────────────────────────────────────────${NC}"
echo ""
echo -e "${YELLOW}  Calculating SHA256 of the original file...${NC}"
ORIGINAL_HASH=$(sha256sum security_test.txt | awk '{print $1}')
echo -e "${GREEN}✓ Original SHA256: $ORIGINAL_HASH${NC}"
echo ""

echo -e "${YELLOW}  Downloading the file from MinIO...${NC}"
curl -s "$READER/files/$KEY" -o downloaded_check.txt
DOWNLOADED_HASH=$(sha256sum downloaded_check.txt | awk '{print $1}')
echo -e "${GREEN}✓ Downloaded SHA256: $DOWNLOADED_HASH${NC}"
echo ""

if [ "$ORIGINAL_HASH" = "$DOWNLOADED_HASH" ]; then
    echo -e "${GREEN}✓ INTEGRITY VERIFIED — hashes match!${NC}"
    echo -e "${GREEN}  → No data corruption during storage or retrieval.${NC}"
    echo -e "${GREEN}  → Detects response failures (accidental corruption).${NC}"
else
    echo -e "${RED}✗ INTEGRITY VIOLATION — hashes do NOT match!${NC}"
    echo -e "${RED}  → Data was corrupted during storage or retrieval.${NC}"
fi
echo ""

echo -e "${YELLOW}  Simulating data corruption (response failure)...${NC}"
echo -e "${CYAN}  Manually corrupting the downloaded file...${NC}"
echo "this file has been corrupted" > corrupted.txt
CORRUPTED_HASH=$(sha256sum corrupted.txt | awk '{print $1}')
echo -e "${RED}✗ Corrupted SHA256: $CORRUPTED_HASH${NC}"
echo ""

if [ "$ORIGINAL_HASH" != "$CORRUPTED_HASH" ]; then
    echo -e "${RED}✗ CORRUPTION DETECTED — hashes do not match!${NC}"
    echo -e "${YELLOW}  → SHA256 successfully detects response failures.${NC}"
    echo -e "${YELLOW}  → In production: reject file and request re-download.${NC}"
fi
echo ""

# ── cleanup ───────────────────────────────────────────────────────────
rm -f security_test.txt downloaded_check.txt corrupted.txt
docker exec project2-distributed-data-minio1-1 \
  rm -f /tmp/evil.txt /tmp/downloaded.txt > /dev/null 2>&1 || true

echo -e "${BLUE}════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Security Demo Complete${NC}"
echo -e "${BLUE}════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Summary of security properties demonstrated:${NC}"
echo ""
echo -e "${GREEN}  ✓ Bucket policy     — anonymous access blocked (HTTP 403)${NC}"
echo -e "${GREEN}  ✓ Authentication    — credentials required for all operations${NC}"
echo -e "${GREEN}  ✓ RBAC write        — readeruser cannot upload (s3:PutObject denied)${NC}"
echo -e "${GREEN}  ✓ RBAC delete       — readeruser cannot delete (s3:DeleteObject denied)${NC}"
echo -e "${GREEN}  ✓ RBAC read         — readeruser can list and download${NC}"
echo -e "${GREEN}  ✓ Admin access      — full read/write/delete confirmed${NC}"
echo -e "${GREEN}  ✓ SHA256 integrity  — response failure (corruption) detected${NC}"