#!/bin/bash

set -e

# Download DocWatch Research Data from S3
# Usage: ./scripts/download_data.sh [signed-url]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$PROJECT_DIR/data"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}DocWatch Research Data Downloader${NC}"
echo "=========================================="
echo ""

# Check if URL is provided as argument
if [ -n "$1" ]; then
    S3_SIGNED_URL="$1"
    echo -e "${GREEN}✓${NC} Using URL from command line argument"
else
    # Load from .env file
    if [ -f "$PROJECT_DIR/.env" ]; then
        source "$PROJECT_DIR/.env"
    else
        echo -e "${RED}✗ Error: .env file not found${NC}"
        echo "Please copy .env.example to .env and configure S3_SIGNED_URL"
        echo "Or provide the signed URL as an argument:"
        echo "  ./scripts/download_data.sh 'https://...'"
        exit 1
    fi
fi

# Validate URL
if [ -z "$S3_SIGNED_URL" ]; then
    echo -e "${RED}✗ Error: S3_SIGNED_URL not set${NC}"
    echo "Please set S3_SIGNED_URL in .env or provide as argument"
    exit 1
fi

# Create data directory
mkdir -p "$DATA_DIR"

# Download file
OUTPUT_FILE="$DATA_DIR/warehouse_export.sql.gz"

echo "Downloading data from S3..."
echo "Destination: $OUTPUT_FILE"
echo ""

if command -v wget &> /dev/null; then
    echo "Using wget..."
    wget -O "$OUTPUT_FILE" "$S3_SIGNED_URL" --progress=bar:force 2>&1
elif command -v curl &> /dev/null; then
    echo "Using curl..."
    curl -L -o "$OUTPUT_FILE" "$S3_SIGNED_URL" --progress-bar
else
    echo -e "${RED}✗ Error: Neither wget nor curl found${NC}"
    echo "Please install wget or curl to download data"
    exit 1
fi

# Check download success
if [ $? -eq 0 ] && [ -f "$OUTPUT_FILE" ]; then
    FILE_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
    echo ""
    echo -e "${GREEN}✓ Download complete!${NC}"
    echo "File: $OUTPUT_FILE"
    echo "Size: $FILE_SIZE"
    echo ""
    echo "Next steps:"
    echo "  1. Start PostgreSQL: docker compose up -d"
    echo "  2. Load data: ./scripts/load_data.sh"
else
    echo -e "${RED}✗ Download failed${NC}"
    exit 1
fi
