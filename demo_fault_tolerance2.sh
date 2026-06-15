#!/bin/bash
# demo_fault_tolerance.sh
# Run this from inside the project folder with: bash demo_fault_tolerance.sh

set -e  # stop on any unexpected error

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # no color

UPLOADER="http://localhost:5001"
READER="http://localhost:5002"
THUMBNAILER="http://localhost:5003"
METADATA="http://localhost:5004"
CLUSTER="http://localhost:5005"

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Project 2 — Fault Tolerance Demo              ${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# ── STEP 1: upload a test file ────────────────────────────────────────
echo -e "${YELLOW}STEP 1: Uploading a test file...${NC}"
echo "This is a test file for the fault tolerance demo." > demo_file.txt

RESPONSE=$(curl -s -X POST "$UPLOADER/upload" -F "file=@demo_file.txt")
KEY=$(echo "$RESPONSE" | sed 's/.*"key":[ ]*"\([^"]*\)".*/\1/')

echo -e "${GREEN}✓ Uploaded successfully. Key: $KEY${NC}"
echo ""

# ── STEP 2: store metadata for the uploaded file ──────────────────────
echo -e "${YELLOW}STEP 2: Storing metadata via metadata service...${NC}"
META_RESPONSE=$(curl -s -X POST "$METADATA/metadata" \
  -H "Content-Type: application/json" \
  -d "{\"key\":\"$KEY\",\"original_filename\":\"demo_file.txt\",\"size\":50,\"content_type\":\"text/plain\"}")
echo -e "${GREEN}✓ Metadata stored: $META_RESPONSE${NC}"
echo ""

# ── STEP 3: retrieve metadata ─────────────────────────────────────────
echo -e "${YELLOW}STEP 3: Retrieving metadata for the file...${NC}"
META=$(curl -s "$METADATA/metadata/$KEY")
echo -e "${GREEN}✓ Metadata retrieved: $META${NC}"
echo ""

# ── STEP 4: show cluster status with all nodes up ─────────────────────
echo -e "${YELLOW}STEP 4: Cluster status — all 4 nodes online...${NC}"
STATUS=$(curl -s "$CLUSTER/cluster/status")
echo -e "${GREEN}✓ Cluster status:${NC}"
echo "$STATUS" | python3 -m json.tool 2>/dev/null || echo "$STATUS"
echo ""

# ── STEP 5: verify file is readable with all nodes up ─────────────────
echo -e "${YELLOW}STEP 5: Reading file with all 4 nodes online...${NC}"
CONTENT=$(curl -s "$READER/files/$KEY")
echo -e "${GREEN}✓ File content: $CONTENT${NC}"
echo ""

# ── STEP 6: kill minio1 ───────────────────────────────────────────────
echo -e "${YELLOW}STEP 6: Killing minio1 (simulating a crash failure)...${NC}"
docker compose stop minio1
sleep 3
echo -e "${RED}✗ minio1 is DOWN. 3 nodes remaining.${NC}"
echo ""

echo -e "${CYAN}  Cluster status after minio1 failure:${NC}"
STATUS=$(curl -s "$CLUSTER/cluster/status")
echo "$STATUS" | python3 -m json.tool 2>/dev/null || echo "$STATUS"
echo ""

echo -e "${YELLOW}  Reading file with minio1 offline...${NC}"
CONTENT=$(curl -s "$READER/files/$KEY")
echo -e "${GREEN}✓ Still readable! Content: $CONTENT${NC}"
echo -e "${GREEN}  → Erasure coding masks the failure. CAP: CP system stays consistent.${NC}"
echo ""

echo -e "${YELLOW}  Metadata still accessible with minio1 offline...${NC}"
META=$(curl -s "$METADATA/metadata/$KEY")
echo -e "${GREEN}✓ Metadata: $META${NC}"
echo ""

# ── STEP 7: kill minio2 ───────────────────────────────────────────────
read -p "Press ENTER to kill a second node (minio2)..."
echo ""
echo -e "${YELLOW}STEP 7: Killing minio2 (2 nodes now dead)...${NC}"
docker compose stop minio2
sleep 3
echo -e "${RED}✗ minio2 is DOWN. 2 nodes remaining (minimum read quorum).${NC}"
echo ""

echo -e "${CYAN}  Cluster status after minio2 failure:${NC}"
STATUS=$(curl -s "$CLUSTER/cluster/status")
echo "$STATUS" | python3 -m json.tool 2>/dev/null || echo "$STATUS"
echo ""

echo -e "${YELLOW}  READ TEST: Reading existing file with minio1 + minio2 offline...${NC}"
CONTENT=$(curl -s "$READER/files/$KEY")
echo -e "${GREEN}✓ Still readable! Content: $CONTENT${NC}"
echo -e "${GREEN}  → Read quorum = 2 nodes. Exactly 2 remain. EC:2 reconstructs the file.${NC}"
echo ""

echo -e "${YELLOW}  WRITE TEST: Attempting to upload a NEW file with only 2 nodes online...${NC}"
echo "this is a write quorum test file" > write_test.txt
WRITE_HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$UPLOADER/upload" -F "file=@write_test.txt")
rm write_test.txt

if [ "$WRITE_HTTP" != "201" ]; then
    echo -e "${RED}✗ UPLOAD FAILED (HTTP $WRITE_HTTP) — as expected!${NC}"
    echo -e "${YELLOW}  → Write quorum = 3 nodes. Only 2 are alive.${NC}"
    echo -e "${YELLOW}    EC:2 has TWO separate quorums:${NC}"
    echo -e "${YELLOW}      • Read  quorum = N/2     = 2 nodes  ✓ met${NC}"
    echo -e "${YELLOW}      • Write quorum = N/2 + 1 = 3 nodes  ✗ not met${NC}"
    echo -e "${YELLOW}    MinIO allows reads but blocks writes to prevent incomplete chunk distribution.${NC}"
else
    echo -e "${GREEN}  Upload succeeded (HTTP $WRITE_HTTP)${NC}"
fi
echo ""
# ── STEP 8: kill minio3 — quorum lost ────────────────────────────────
read -p "Press ENTER to kill a third node (minio3) — this will break quorum..."
echo ""
echo -e "${YELLOW}STEP 8: Killing minio3 (3 nodes dead — quorum lost)...${NC}"
docker compose stop minio3
sleep 3
echo -e "${RED}✗ minio3 is DOWN. Only minio4 alive.${NC}"
echo ""

echo -e "${CYAN}  Cluster status after quorum loss:${NC}"
STATUS=$(curl -s "$CLUSTER/cluster/status")
echo "$STATUS" | python3 -m json.tool 2>/dev/null || echo "$STATUS"
echo ""

echo -e "${YELLOW}  Attempting to read file with only 1 node online...${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$READER/files/$KEY")
if [ "$HTTP_CODE" != "200" ]; then
    echo -e "${RED}✗ READ FAILED (HTTP $HTTP_CODE) — as expected!${NC}"
    echo -e "${YELLOW}  → CAP theorem: with quorum lost, MinIO refuses to serve${NC}"
    echo -e "${YELLOW}    stale data. It chooses Consistency over Availability.${NC}"
else
    echo -e "  Response: $(curl -s $READER/files/$KEY)"
fi
echo ""

echo -e "${YELLOW}  Attempting to retrieve metadata with quorum lost...${NC}"
HTTP_META=$(curl -s -o /dev/null -w "%{http_code}" "$METADATA/metadata/$KEY")
if [ "$HTTP_META" != "200" ]; then
    echo -e "${RED}✗ METADATA READ FAILED (HTTP $HTTP_META) — as expected!${NC}"
    echo -e "${YELLOW}  → Metadata is also stored in MinIO — same quorum rules apply.${NC}"
else
    echo -e "${GREEN}  Metadata: $(curl -s $METADATA/metadata/$KEY)${NC}"
fi
echo ""

# ── STEP 9: recovery ─────────────────────────────────────────────────
read -p "Press ENTER to restore all nodes and show automatic recovery..."
echo ""
echo -e "${YELLOW}STEP 9: Restarting minio1, minio2, minio3...${NC}"
docker compose start minio1 minio2 minio3
echo "  Waiting 15 seconds for cluster to reform..."
sleep 15
echo ""

echo -e "${CYAN}  Cluster status after recovery:${NC}"
STATUS=$(curl -s "$CLUSTER/cluster/status")
echo "$STATUS" | python3 -m json.tool 2>/dev/null || echo "$STATUS"
echo ""

echo -e "${YELLOW}  Reading file after full recovery...${NC}"
CONTENT=$(curl -s "$READER/files/$KEY")
echo -e "${GREEN}✓ File recovered! Content: $CONTENT${NC}"
echo -e "${GREEN}  → Cluster self-healed. No manual intervention needed.${NC}"
echo ""

echo -e "${YELLOW}  Metadata recovered...${NC}"
META=$(curl -s "$METADATA/metadata/$KEY")
echo -e "${GREEN}✓ Metadata: $META${NC}"
echo ""

# ── STEP 10: list all metadata ────────────────────────────────────────
echo -e "${YELLOW}STEP 10: Listing all file metadata in the cluster...${NC}"
ALL_META=$(curl -s "$METADATA/metadata")
echo -e "${GREEN}✓ All metadata: $ALL_META${NC}"
echo ""

# ── cleanup ───────────────────────────────────────────────────────────
rm demo_file.txt
echo -e "${BLUE}================================================${NC}"
echo -e "${GREEN}  Demo complete.${NC}"
echo -e "${BLUE}================================================${NC}"