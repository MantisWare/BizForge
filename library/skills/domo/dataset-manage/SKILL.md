---
name: domo/dataset-manage
description: >
  Create, update, query, and manage Domo DataSets via the Platform and Product
  APIs. Covers schema definition, CSV import/export, Stream API for large
  ingestion, PDP policies, and dataset history management.
  Triggers on: "dataset", "data set", "import data", "stream api", "pdp", "data permissions"
---

# /domo/dataset-manage

> Manage Domo DataSets via API — create schemas, import/export data, stream large datasets, and configure PDP.

## Purpose

DataSets are the foundation of Domo's data layer. This skill covers the full lifecycle: creating datasets with schema definitions, importing data via CSV or the Stream API (for large/incremental loads), configuring Personalized Data Permissions (PDP), managing dataset history, and querying data programmatically.

## Usage

```bash
# Create a new dataset with schema
/domo/dataset-manage create --name "Sales Q4" --schema schema.json

# Import CSV data
/domo/dataset-manage import --dataset-id DS123 --file data.csv --mode replace

# Stream large dataset (multi-part upload)
/domo/dataset-manage stream --dataset-id DS123 --parts 10

# Configure PDP policy
/domo/dataset-manage pdp --dataset-id DS123 --policy "Region Filter"
```

## Process

### Step 1: Create DataSet

**Via Platform API (OAuth):**
```
POST /v1/datasets
Headers: Authorization: Bearer {access_token}
Body: {
  "name": "Dataset Name",
  "description": "Description",
  "schema": {
    "columns": [
      { "type": "STRING", "name": "customer_name" },
      { "type": "LONG", "name": "order_count" },
      { "type": "DOUBLE", "name": "revenue" },
      { "type": "DATE", "name": "order_date" },
      { "type": "DATETIME", "name": "created_at" }
    ]
  }
}
```

**Column Types:** `STRING`, `LONG`, `DOUBLE`, `DATE`, `DATETIME`

### Step 2: Import Data (Small Datasets)

```
PUT /v1/datasets/{DATASET_ID}/data
Headers: Content-Type: text/csv
Body: CSV content (RFC-4180 format)
```

CSV requirements (RFC-4180):
- Comma-delimited fields.
- Double-quote fields containing commas, newlines, or quotes.
- Escape quotes by doubling them (`""`).
- First row can be header (matched to schema column names).

### Step 3: Stream API (Large Datasets)

For datasets over 1M rows or requiring incremental updates:

1. **Create Stream:**
```
POST /v1/streams
Body: { "dataSet": { "id": "DATASET_ID" }, "updateMethod": "REPLACE" }
```

2. **Create Execution:**
```
POST /v1/streams/{STREAM_ID}/executions
```

3. **Upload Parts (parallelizable):**
```
PUT /v1/streams/{STREAM_ID}/executions/{EXEC_ID}/part/{PART_ID}
Headers: Content-Type: text/csv
Body: CSV chunk
```
Parts can be uploaded simultaneously in separate threads. Each part needs a distinct, sequentially ordered PART_ID. Compress as gzip (`application/gzip`) for speed.

4. **Commit Execution:**
```
PUT /v1/streams/{STREAM_ID}/executions/{EXEC_ID}/commit
```

**Update Methods:** `REPLACE` (full refresh), `APPEND` (add rows)

### Step 4: Query Data

**From Custom App:**
```javascript
const data = await domo.get('/data/v1/sales_data?limit=100');
```

**Via SQL (toolkit):**
```javascript
import { SqlClient } from '@domoinc/toolkit';
const results = await SqlClient.query('SELECT * FROM sales WHERE amount > 1000');
```

### Step 5: Personalized Data Permissions (PDP)

PDP restricts which rows users see based on policies:

```
POST /v1/datasets/{DATASET_ID}/policies
Body: {
  "name": "Region Policy",
  "type": "user",
  "users": [12345],
  "filters": [
    { "column": "region", "values": ["West", "Northwest"] }
  ]
}
```

Policy types:
- **User-based**: Filter rows per user/group.
- **System**: Apply to all non-admin users.

### Step 6: Dataset History and Management

- **List datasets:** `GET /v1/datasets?limit=50&offset=0`
- **Get metadata:** `GET /v1/datasets/{ID}`
- **Update schema:** `PUT /v1/datasets/{ID}` (add columns only)
- **Delete dataset:** `DELETE /v1/datasets/{ID}`
- **Export data:** `GET /v1/datasets/{ID}/data?includeHeader=true`

## Key References

- Platform API: `/v1/datasets`, `/v1/streams`
- Column types: STRING, LONG, DOUBLE, DATE, DATETIME
- CSV format: RFC-4180
- Stream API: Create → Execute → Upload Parts → Commit
- PDP: Row-level security via policies
- Update methods: REPLACE, APPEND
- `@domoinc/toolkit` SqlClient for SQL queries
- `domo.js` `domo.get('/data/v1/{alias}')` for app context

## Examples

```bash
# Create dataset and import initial data
/domo/dataset-manage create --name "Orders" --columns "id:LONG,name:STRING,total:DOUBLE"
/domo/dataset-manage import --dataset-id DS456 --file orders.csv

# Stream a 5M row dataset in 10 parallel parts
/domo/dataset-manage stream --dataset-id DS456 --parts 10 --compress gzip

# Add PDP policy for regional access
/domo/dataset-manage pdp --dataset-id DS456 --column region --users "team-west" --values "West,Northwest"
```
