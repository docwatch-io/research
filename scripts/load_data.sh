#!/bin/bash

set -e

# Load DocWatch Research Data into PostgreSQL
# Usage: ./scripts/load_data.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$PROJECT_DIR/data"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}DocWatch Research Data Loader${NC}"
echo "=========================================="
echo ""

# Load environment variables
if [ -f "$PROJECT_DIR/.env" ]; then
    source "$PROJECT_DIR/.env"
else
    echo -e "${YELLOW}⚠ Warning: .env file not found, using defaults${NC}"
    POSTGRES_USER=${POSTGRES_USER:-researcher}
    POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-research}
    POSTGRES_DB=${POSTGRES_DB:-docwatch}
    POSTGRES_PORT=${POSTGRES_PORT:-5432}
fi

# Check if compressed data file exists
COMPRESSED_FILE="$DATA_DIR/warehouse_export.sql.gz"
DECOMPRESSED_FILE="$DATA_DIR/warehouse_export.sql"

if [ ! -f "$COMPRESSED_FILE" ] && [ ! -f "$DECOMPRESSED_FILE" ]; then
    echo -e "${RED}✗ Error: Data file not found${NC}"
    echo "Expected: $COMPRESSED_FILE"
    echo ""
    echo "Please run: ./scripts/download_data.sh <signed-url>"
    exit 1
fi

# Check if PostgreSQL is running
echo "Checking PostgreSQL connection..."
export PGPASSWORD="$POSTGRES_PASSWORD"

if ! docker compose ps | grep -q "docwatch-research-db.*running"; then
    echo -e "${YELLOW}⚠ PostgreSQL container not running${NC}"
    echo "Starting PostgreSQL..."
    docker compose up -d postgres
    echo "Waiting for PostgreSQL to be ready..."
    sleep 10
fi

# Test connection
if ! docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1" > /dev/null 2>&1; then
    echo -e "${RED}✗ Error: Cannot connect to PostgreSQL${NC}"
    echo "Please ensure PostgreSQL is running: docker compose up -d"
    exit 1
fi

echo -e "${GREEN}✓${NC} PostgreSQL is ready"
echo ""

# Decompress if needed
if [ -f "$COMPRESSED_FILE" ] && [ ! -f "$DECOMPRESSED_FILE" ]; then
    echo "Decompressing data file..."
    gunzip -k "$COMPRESSED_FILE"
    echo -e "${GREEN}✓${NC} Decompression complete"
    echo ""
fi

# Check file size
FILE_SIZE=$(du -h "$DECOMPRESSED_FILE" | cut -f1)
echo "Loading data into PostgreSQL..."
echo "File: $DECOMPRESSED_FILE"
echo "Size: $FILE_SIZE"
echo ""
echo -e "${YELLOW}⚠ This may take 30-60 minutes for large datasets${NC}"
echo ""

# Start timer
START_TIME=$(date +%s)

# Step 1: Load schema (creates warehouse schema and tables)
echo "Loading schema..."
cat "$PROJECT_DIR/schema.sql" | docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
echo -e "${GREEN}✓${NC} Schema loaded"
echo ""

# Step 2: Load data
echo "Loading data (this will take a while)..."
cat "$DECOMPRESSED_FILE" | docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"

# End timer
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

echo ""
echo -e "${GREEN}✓ Data load complete!${NC}"
echo "Duration: ${MINUTES}m ${SECONDS}s"
echo ""

# Verify data
echo "Verifying data..."
RECORD_COUNT=$(docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "SELECT COUNT(*) FROM warehouse.provider" | tr -d ' ')

echo -e "${GREEN}✓${NC} Found $RECORD_COUNT provider records"
echo ""

# Show table sizes
echo "Table sizes:"
docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
SELECT
    schemaname || '.' || tablename AS table_name,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
    n_live_tup AS rows
FROM pg_stat_user_tables
WHERE schemaname = 'warehouse'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;
"

echo ""
echo -e "${GREEN}✓ Setup complete!${NC}"
echo ""
echo "You can now query the database:"
echo "  docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB"
echo ""
echo "Or connect with your favorite SQL client:"
echo "  Host: localhost"
echo "  Port: $POSTGRES_PORT"
echo "  User: $POSTGRES_USER"
echo "  Password: $POSTGRES_PASSWORD"
echo "  Database: $POSTGRES_DB"
