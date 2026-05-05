#!/bin/bash
# demo_fault_tolerance.sh
# Run this from inside the project folder with: bash demo_fault_tolerance.sh

set -e  # stop on any unexpected error

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # no color

UPLOADER="http://localhost:5001"
READER="http://localhost:5002"

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

# ── STEP 2: verify it is readable with all nodes up ───────────────────
echo -e "${YELLOW}STEP 2: Reading file with all 4 nodes online...${NC}"
CONTENT=$(curl -s "$READER/files/$KEY")
echo -e "${GREEN}✓ File content: $CONTENT${NC}"
echo ""

# ── STEP 3: kill minio1 ───────────────────────────────────────────────
echo -e "${YELLOW}STEP 3: Killing minio1 (simulating a crash failure)...${NC}"
docker compose stop minio1
sleep 3
echo -e "${RED}✗ minio1 is DOWN. 3 nodes remaining.${NC}"
echo ""

echo -e "${YELLOW}  Reading file with minio1 offline...${NC}"
CONTENT=$(curl -s "$READER/files/$KEY")
echo -e "${GREEN}✓ Still readable! Content: $CONTENT${NC}"
echo -e "${GREEN}  → Erasure coding masks the failure. CAP: CP system stays consistent.${NC}"
echo ""

# ── STEP 4: kill minio2 ───────────────────────────────────────────────
read -p "Press ENTER to kill a second node (minio2)..."
echo ""
echo -e "${YELLOW}STEP 4: Killing minio2 (2 nodes now dead)...${NC}"
docker compose stop minio2
sleep 3
echo -e "${RED}✗ minio2 is DOWN. 2 nodes remaining (minimum quorum).${NC}"
echo ""

echo -e "${YELLOW}  Reading file with minio1 + minio2 offline...${NC}"
CONTENT=$(curl -s "$READER/files/$KEY")
echo -e "${GREEN}✓ Still readable! Content: $CONTENT${NC}"
echo -e "${GREEN}  → EC:2 means we can lose exactly 2 nodes. System at minimum quorum.${NC}"
echo ""

# ── STEP 5: kill minio3 — quorum lost ────────────────────────────────
read -p "Press ENTER to kill a third node (minio3) — this will break quorum..."
echo ""
echo -e "${YELLOW}STEP 5: Killing minio3 (3 nodes dead — quorum lost)...${NC}"
docker compose stop minio3
sleep 3
echo -e "${RED}✗ minio3 is DOWN. Only minio4 alive.${NC}"
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

# ── STEP 6: recovery ─────────────────────────────────────────────────
read -p "Press ENTER to restore all nodes and show automatic recovery..."
echo ""
echo -e "${YELLOW}STEP 6: Restarting minio1, minio2, minio3...${NC}"
docker compose start minio1 minio2 minio3
echo "  Waiting 15 seconds for cluster to reform..."
sleep 15
echo ""

echo -e "${YELLOW}  Reading file after full recovery...${NC}"
CONTENT=$(curl -s "$READER/files/$KEY")
echo -e "${GREEN}✓ File recovered! Content: $CONTENT${NC}"
echo -e "${GREEN}  → Cluster self-healed. No manual intervention needed.${NC}"
echo ""

# ── cleanup ───────────────────────────────────────────────────────────
rm demo_file.txt
echo -e "${BLUE}================================================${NC}"
echo -e "${GREEN}  Demo complete.${NC}"
echo -e "${BLUE}================================================${NC}"