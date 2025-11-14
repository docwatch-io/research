# docwatch.io Healthcare Provider Consolidation Dataset

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Website](https://img.shields.io/badge/website-docwatch.io-blue)](https://docwatch.io)

> **Complete historical dataset of healthcare provider consolidation (2007-2025)**
>
> 22.6M provider records • 24.9M community assignments • 180K facilities • Full SCD Type 2 tracking

---

## Overview

This repository provides a **self-hosted PostgreSQL database** containing the complete [docwatch.io](https://docwatch.io) healthcare provider consolidation dataset. The database uses Slowly Changing Dimension (SCD) Type 2 architecture to track provider information changes over time, enabling both current snapshot queries and full historical lineage analysis.

**Key Features:**
- ✅ **18 years of data**: 2007-2025 (annual 2007-2017, monthly 2017-2025)
- ✅ **Full historical tracking**: Every provider change creates a new record with temporal validity
- ✅ **Community detection**: Providers linked to hospitals and medical groups
- ✅ **Self-hosted**: Runs entirely on your machine (no cloud costs)
- ✅ **Privacy-friendly**: Your research, your infrastructure

**Research Applications**: Labor economics, industrial organization, health services research, policy analysis, geographic economics

---

## Quick Start

### Prerequisites

- **Docker Desktop** installed ([Download](https://www.docker.com/products/docker-desktop))
- **150 GB free disk space** (100GB for data, 50GB for working space)
- **8GB+ RAM recommended** (4GB minimum)
- **Approved access** from [docwatch.io](https://docwatch.io) team (you'll receive a time-limited S3 download URL)

### Installation

```bash
# 1. Clone repository
git clone https://github.com/docwatch-io/research.git
cd research

# 2. Configure environment
cp .env.example .env
nano .env  # Add S3_SIGNED_URL from docwatch.io team

# 3. Download data (~35-45GB compressed, 10-30 min)
./scripts/download_data.sh

# 4. Start PostgreSQL
docker compose up -d

# 5. Load data (~30-60 minutes)
./scripts/load_data.sh

# 6. Connect and query!
docker compose exec postgres psql -U researcher -d postgres
```

**Verify installation:**
```sql
SELECT COUNT(*) FROM warehouse.provider;
-- Should return ~22,600,000
```

---

## Dataset Contents

### Three Core Tables (~107 GB)

| Table | Size | Records | Description |
|-------|------|---------|-------------|
| `warehouse.provider` | 100 GB | 22.6M | Full SCD Type 2 provider history with JSON fields |
| `warehouse.community` | 6.8 GB | 24.9M | Provider-community assignments over time |
| `warehouse.place_of_service` | 124 MB | 180K | Facility reference table (CCN lookup) |

### Data Coverage

- **Unique NPIs**: 5M+ providers (~60-65% US coverage)
- **Temporal snapshots**: 127 snapshots (2007-2025)
- **Community detection**:
  - Institutional (CCN-based): 19.6% of providers
  - Practice (address-based): 40-45% of providers
- **Geographic coverage**: All 50 US states + territories

---

## Database Schema

### `warehouse.provider` - Provider Historical Records

**SCD Type 2 tracking with JSON fields for flexibility**

**Key Columns:**
- `npi` (VARCHAR): National Provider Identifier
- `effective_date` (DATE): When this version became effective
- `end_date` (DATE): When superseded (NULL = current)
- `is_current` (BOOLEAN): True if current active record
- `record_hash` (VARCHAR): SHA-256 for change detection

**JSON Fields:**
- `basic`: Name, credential, gender, enumeration_date
- `addresses`: Mailing and practice locations
- `taxonomies`: Specialty codes (primary + additional)
- `identifiers`: Other ID systems (Medicaid, state licenses)
- `endpoints`: FHIR endpoints
- `other_names`: Previous legal names

**Example query:**
```sql
-- Get current providers by state
SELECT
    (basic->>'state') as state,
    COUNT(DISTINCT npi) as total_providers
FROM warehouse.provider
WHERE is_current = true
GROUP BY state
ORDER BY total_providers DESC;
```

### `warehouse.community` - Community Assignments

**Tracks provider-community memberships over time**

**Key Columns:**
- `npi`: Provider NPI
- `canonical_community_id`: Community identifier (CCN from place_of_service)
- `effective_date`, `end_date`, `is_current`: SCD Type 2 tracking

**Community Detection Logic:**

Two-tier graph analysis:
1. **Institutional Tier**: Providers sharing same CCN (hospitals, facilities)
2. **Practice Tier**: Providers sharing same practice address (medical groups)

**Example query:**
```sql
-- Largest communities by provider count
SELECT
    c.canonical_community_id,
    pos.facility_name,
    pos.city,
    pos.state,
    COUNT(DISTINCT c.npi) as provider_count
FROM warehouse.community c
LEFT JOIN warehouse.place_of_service pos
    ON c.canonical_community_id = pos.ccn
    AND pos.is_current = true
WHERE c.is_current = true
GROUP BY c.canonical_community_id, pos.facility_name, pos.city, pos.state
ORDER BY provider_count DESC
LIMIT 20;
```

### `warehouse.place_of_service` - Facility Reference

**CMS facility lookup table (CCN → facility name)**

**Key Columns:**
- `ccn`: CMS Certification Number (primary key)
- `facility_name`: Official name
- `address`, `city`, `state`, `zip_code`
- `facility_type`: Hospital, SNF, etc.
- `effective_date`, `end_date`, `is_current`: SCD Type 2 tracking

**Example query:**
```sql
-- Get all providers who work at the Mayo Clinic
SELECT
    p.npi,
    p.basic,
    p.enumeration_type,
    p.basic->>'first_name' as first_name,
    p.basic->>'last_name' as last_name,
    pos.facility_name,
    pos.city,
    pos.state
FROM warehouse.provider p
JOIN warehouse.community c ON p.npi = c.npi
JOIN warehouse.place_of_service pos ON c.canonical_community_id = pos.ccn
WHERE 
  pos.facility_name like '%MAYO CLINIC%'
  and p.enumeration_type = 'NPI-1'
  and pos.state = 'MN'
  and p.is_current=true
;
  ```

### Point-in-Time Queries

Query provider state at any historical date:

```sql
-- Provider state on January 1, 2020
SELECT *
FROM warehouse.provider
WHERE npi = '1134194152'
  AND effective_date <= '2020-01-01'
  AND (end_date > '2020-01-01' OR end_date IS NULL);


-- Community membership on January 1, 2020
SELECT
    c.npi,
    c.canonical_community_id,
    pos.facility_name
FROM warehouse.community c
JOIN warehouse.place_of_service pos ON c.canonical_community_id = pos.ccn
WHERE c.npi = '1134194152'
  AND c.effective_date <= '2020-01-01'
  AND (c.end_date > '2020-01-01' OR c.end_date IS NULL)
  AND pos.effective_date <= '2020-01-01'
  AND (pos.end_date > '2020-01-01' OR pos.end_date IS NULL);
```

---

## Usage Examples

### Python with pandas

```python
import psycopg2
import pandas as pd

# Connect to local database
conn = psycopg2.connect(
    host='localhost',
    port=5432,
    database='postgres',
    user='researcher',
    password='research'
)

# Example: Provider consolidation trend
query = """
SELECT
    DATE_TRUNC('year', effective_date) as year,
    COUNT(DISTINCT npi) as providers_changing_communities,
    COUNT(DISTINCT canonical_community_id) as distinct_communities
FROM warehouse.community
WHERE change_type IN ('INSERT', 'UPDATE')
GROUP BY year
ORDER BY year;
"""

df = pd.read_sql(query, conn)
print(df)

conn.close()
```

### R

```r
library(RPostgreSQL)
library(dplyr)

# Connect to database
drv <- dbDriver("PostgreSQL")
con <- dbConnect(drv,
                 host = "localhost",
                 port = 5432,
                 dbname = "postgres",
                 user = "researcher",
                 password = "research")

# Example query
query <- "
SELECT
    (basic->>'state') as state,
    COUNT(DISTINCT npi) as total_providers
FROM warehouse.provider
WHERE is_current = true
GROUP BY state
ORDER BY total_providers DESC;
"

df <- dbGetQuery(con, query)
print(df)

dbDisconnect(con)
```

### psql (Interactive)

```bash
# Connect to database
docker compose exec postgres psql -U researcher -d postgres

# Inside psql:
\dt warehouse.*           # List all tables
\d warehouse.provider     # Describe provider table

# Run example query
SELECT
    COUNT(*) as total_providers,
    SUM(CASE WHEN is_current THEN 1 ELSE 0 END) as current_providers
FROM warehouse.provider;

\q  # Exit
```

---

## Common Research Queries

### 1. Providers in Institutional vs Practice Communities

```sql
SELECT
    CASE
        WHEN pos.ccn IS NOT NULL THEN 'Institutional'
        ELSE 'Practice-Only'
    END as community_type,
    COUNT(DISTINCT c.npi) as provider_count,
    COUNT(DISTINCT c.canonical_community_id) as community_count
FROM warehouse.community c
LEFT JOIN warehouse.place_of_service pos
    ON c.canonical_community_id = pos.ccn
    AND pos.is_current = true
WHERE c.is_current = true
GROUP BY community_type;
```

### 2. Provider Community Changes Over Time

```sql
SELECT
    npi,
    effective_date,
    end_date,
    canonical_community_id,
    change_type
FROM warehouse.community
WHERE npi = '1234567890'
ORDER BY effective_date;
```

### 3. State-Level Provider Counts

```sql
SELECT
    (basic->>'state') as state,
    COUNT(DISTINCT npi) as total_providers
FROM warehouse.provider
WHERE is_current = true
GROUP BY state
ORDER BY total_providers DESC;
```

---

## Detailed Setup Instructions

### Step 1: Install Docker

#### macOS
1. Download [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop)
2. Drag to Applications and launch
3. Verify: `docker --version && docker compose version`

#### Windows
1. Download [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop)
2. Enable WSL 2 if prompted
3. Verify in PowerShell: `docker --version`

**Note**: Use WSL for best compatibility on Windows

#### Linux (Ubuntu/Debian)
```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose
sudo usermod -aG docker $USER
newgrp docker
```

### Step 2: Configure Environment

```bash
cp .env.example .env
nano .env  # or vim, code, etc.
```

Add your S3 signed URL (provided after approval):
```bash
S3_SIGNED_URL=https://docwatch-research-data.s3.amazonaws.com/warehouse_export.sql.gz?X-Amz-...
```

**Notes:**
- URLs expire after 7 days
- Keep URL private (contains auth tokens)
- Contact [docwatch.io team](https://docwatch.io) if URL expires

### Step 3: Download Data

```bash
./scripts/download_data.sh
```

**What happens:**
- Downloads ~35-45GB compressed file
- Saves to `data/warehouse_export.sql.gz`
- Takes 10-30 minutes (depends on connection speed)

### Step 4: Start PostgreSQL

```bash
docker compose up -d
docker compose ps  # Verify it's running
```

**Troubleshooting:**
- **Port in use?** Edit `.env` and set `POSTGRES_PORT=5433`
- **Docker not running?** Launch Docker Desktop first

### Step 5: Load Data

```bash
./scripts/load_data.sh
```

**What happens:**
- Decompresses SQL file (~120-150GB)
- Loads into PostgreSQL via `psql`
- Creates tables, indexes, constraints
- Takes 30-60 minutes (SSD) or 60-90 minutes (HDD)

**Verify:**
```bash
docker compose exec postgres psql -U researcher -d postgres -c "
SELECT
    schemaname || '.' || tablename AS table_name,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
    n_live_tup AS rows
FROM pg_stat_user_tables
WHERE schemaname = 'warehouse'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
"
```

Expected output:
```
            table_name        |  size   |   rows
------------------------------+---------+----------
 warehouse.provider           | 100 GB  | 22600000
 warehouse.community          | 6.8 GB  | 24900000
 warehouse.place_of_service   | 124 MB  |   180000
```

---

## Common Tasks

### Stopping/Starting PostgreSQL

```bash
# Stop (keeps data)
docker compose stop

# Start again
docker compose up -d

# Stop and remove container (keeps data in volume)
docker compose down
```

### Viewing Logs

```bash
docker compose logs -f postgres        # Real-time
docker compose logs --tail=100 postgres  # Last 100 lines
```

### Backing Up Your Database

```bash
# Export to SQL
docker compose exec -T postgres pg_dump -U researcher -d postgres > backup.sql

# Compress
gzip backup.sql
```

### Updating to Newer Dataset

```bash
docker compose down
docker volume rm research_postgres_data  # ⚠️ Deletes local data
./scripts/download_data.sh <new-url>
docker compose up -d
./scripts/load_data.sh
```

---

## Performance Tips

### For Large Queries

```sql
-- Increase work memory for session
SET work_mem = '256MB';

-- Analyze query performance
EXPLAIN ANALYZE SELECT ...;

-- Rebuild statistics after data load
VACUUM ANALYZE;
```

### Docker Resource Allocation

If queries are slow:
- **macOS/Windows**: Docker Desktop → Settings → Resources
  - Memory: 8GB+
  - CPU: 4+ cores
- **Linux**: No limits (uses all available resources)

### Custom Indexes

```sql
-- Example: Index on provider gender
CREATE INDEX idx_provider_gender ON warehouse.provider ((basic->>'gender'));

-- Update statistics
ANALYZE warehouse.provider;
```

---

## Troubleshooting

### Port Already in Use

```bash
# Option 1: Stop existing PostgreSQL
sudo systemctl stop postgresql  # Linux
brew services stop postgresql   # macOS

# Option 2: Use different port
# Edit .env: POSTGRES_PORT=5433
```

### Out of Disk Space

```bash
df -h  # Check available space
docker system prune -a  # Clear Docker cache
docker volume prune  # Clear old volumes
```

### Cannot Connect

```bash
docker compose ps  # Check if running
docker compose logs postgres  # Check errors
docker compose restart postgres  # Restart
```

### Data Load Interrupted

```bash
# Safe to re-run (drops/recreates tables)
./scripts/load_data.sh
```

---

## Data Quality Notes

### Coverage
- **60-65% of US providers**: Not all NPIs actively maintain records
- **Temporal resolution**:
  - 2007-2017: Annual snapshots
  - 2017-2025: Monthly snapshots
- **Community detection**: Institutional (19.6%) + Practice (40-45%)

### Known Limitations
- Address standardization varies (minor formatting differences)
- Community detection may split/merge over time (algorithm sensitivity)
- Inactive NPIs: `is_current = false` may indicate deactivation, relocation, or deceased
- JSON field completeness varies by provider

### Data Integrity Checks

```sql
-- Check for duplicate current records (should be 0)
SELECT npi, COUNT(*)
FROM warehouse.provider
WHERE is_current = true
GROUP BY npi
HAVING COUNT(*) > 1;

-- Check for overlapping date ranges (should be 0)
SELECT p1.npi, p1.effective_date, p1.end_date, p2.effective_date, p2.end_date
FROM warehouse.provider p1
JOIN warehouse.provider p2 ON p1.npi = p2.npi AND p1.id != p2.id
WHERE p1.effective_date < COALESCE(p2.end_date, '9999-12-31')
  AND COALESCE(p1.end_date, '9999-12-31') > p2.effective_date;
```

---

## Citation

When using this dataset in research, please cite:

```
docwatch.io Healthcare Provider Consolidation Dataset (2007-2025)
Available at: https://github.com/docwatch-io/research
Accessed: [DATE]
```

### BibTeX

```bibtex
@misc{docwatch2025dataset,
  author = {{docwatch.io Research Team}},
  title = {NPPES Provider Network Longitudinal Dataset (2007-2025)},
  year = {2025},
  version = {1.0},
  url = {https://github.com/docwatch-io/research},
  note = {Accessed: [date]}
}
```

See `CITATION.cff` for additional formats.

---

## License

**Code & Documentation**: MIT License (see `LICENSE`)

**Data**: Available for academic use. Commercial use requires separate licensing.

**Data Sources:**
- CMS NPPES Database: Public domain
- CMS CCN Data: Public domain
- NUCC Taxonomy Codes: Public domain

---

## Support

- **Website**: [docwatch.io](https://docwatch.io)
- **GitHub Issues**: https://github.com/docwatch-io/research/issues
- **Email**: research@docwatch.io

### Common Questions

**Q: How much does this cost?**
A: Free for academic use. You only pay for your own compute (local PostgreSQL).

**Q: Can I share the data?**
A: Data is for approved researchers only. Colleagues should apply separately.

**Q: Can I publish using this data?**
A: Yes! Please cite the dataset and share preprints with us.

**Q: What if I need custom aggregations?**
A: Contact research@docwatch.io for collaboration opportunities.

**Q: Is this the same data powering docwatch.io?**
A: Yes, this is a snapshot of the production warehouse data from [docwatch.io](https://docwatch.io), updated quarterly.

---

## Acknowledgments

**Data Source**: Centers for Medicare & Medicaid Services (CMS) NPPES Historical Files (2007-2025)

**Community Detection**: Leiden algorithm (Traag, Waltman, & van Eck, 2019)

**Funding**: Self-funded by [docwatch.io](https://docwatch.io) (no conflicts of interest)

---

**Last Updated**: 2025-11-14
**Dataset Version**: 1.0
