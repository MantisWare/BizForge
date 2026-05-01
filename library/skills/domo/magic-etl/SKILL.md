---
name: domo/magic-etl
description: >
  Design and configure Magic ETL dataflows including transformations, joins,
  scripting tiles, data science tiles, JSON Expand, MySQL DataFlow patterns,
  and scheduling for automated data pipelines.
  Triggers on: "magic etl", "dataflow", "etl", "transform data", "scripting tile", "json expand"
---

# /domo/magic-etl

> Design Magic ETL dataflows with transformations, scripting tiles, and automated scheduling.

## Purpose

Magic ETL is Domo's visual data transformation engine. This skill covers designing dataflows with drag-and-drop tiles, writing custom transformation logic in scripting tiles (Python/R), using data science tiles for ML, configuring JSON Expand for nested data, creating MySQL DataFlow patterns for complex SQL-based transformations, and scheduling automated execution.

## Usage

```bash
# Design a new ETL pipeline
/domo/magic-etl design --name "Sales Transform" --input "Raw Sales" --output "Clean Sales"

# Add scripting tile
/domo/magic-etl script --dataflow "Sales Transform" --lang python --code transform.py

# Schedule execution
/domo/magic-etl schedule --dataflow "Sales Transform" --cron "0 6 * * *"
```

## Process

### Step 1: Dataflow Design
A Magic ETL dataflow consists of connected tiles:

```
[Input DataSet] → [Transform Tiles] → [Output DataSet]
```

**Input tiles**: Select source datasets.
**Transform tiles**: Apply operations (filter, join, group, formula, etc.).
**Output tiles**: Write results to destination datasets.

### Step 2: Core Transformation Tiles

| Tile | Purpose |
|------|---------|
| Filter Rows | Remove rows based on conditions |
| Select Columns | Choose/rename columns |
| Group By | Aggregate with SUM, AVG, COUNT, etc. |
| Join | Combine datasets (inner, left, right, full) |
| Union | Stack datasets vertically |
| Formula | Create calculated columns (Beast Mode syntax) |
| Text | String manipulation (split, concat, trim, replace) |
| Date | Date operations (extract, add, diff) |
| Rank & Window | Window functions (rank, row_number, lag, lead) |
| Pivot | Reshape rows to columns |
| Unpivot | Reshape columns to rows |
| JSON Expand | Flatten nested JSON into columns |

### Step 3: JSON Expand
For datasets containing JSON columns:
1. Select the JSON column to expand.
2. Define the JSON path to extract.
3. Specify output column name and type.
4. Handle arrays by expanding to multiple rows or selecting index.

```
Input: { "order": { "items": [{"sku": "A1", "qty": 2}] } }
Path: $.order.items[*].sku → Output column: item_sku (STRING)
Path: $.order.items[*].qty → Output column: item_qty (LONG)
```

### Step 4: Scripting Tiles (Python/R)

**Python Tile:**
```python
# Input: dataframe named 'df' with all input columns
import pandas as pd

# Transform
df['revenue'] = df['quantity'] * df['price']
df['margin_pct'] = (df['revenue'] - df['cost']) / df['revenue'] * 100

# Output: modified df is written to output dataset
```

**R Tile:**
```r
# Input: dataframe named 'df'
library(dplyr)

df <- df %>%
  mutate(revenue = quantity * price) %>%
  filter(revenue > 0)

# Output: modified df
```

### Step 5: Data Science Tiles
- **Classification**: Predict categories (logistic regression, random forest).
- **Regression**: Predict numeric values.
- **Clustering**: Group similar records.
- **Anomaly Detection**: Find outliers.
- **Forecasting**: Time-series predictions.

### Step 6: MySQL DataFlow Pattern
For complex SQL transformations (legacy/advanced):
1. Create a MySQL DataFlow in Domo.
2. Define transform SQL in JSON format.
3. Inject via Dev Tools > DataFlow JSON editor.
4. Wire input/output datasets.

Column naming rules for MySQL DataFlows:
- No spaces, `$`, or `#` in column names.
- Use underscores for separators.
- Preserve Kamaji Calendar rows where required.

### Step 7: Scheduling
Configure automated execution:
- **Manual**: Run on demand.
- **Scheduled**: Cron-based (e.g., `0 6 * * *` for daily at 6 AM).
- **Triggered**: Run when input datasets update.
- **Chained**: Run after another dataflow completes.

### Step 8: Best Practices
- Keep dataflows focused (single transformation purpose).
- Use descriptive tile names for maintainability.
- Monitor execution time and optimize slow joins.
- Use scripting tiles only when visual tiles are insufficient.
- Document expected input schemas at the dataflow level.

## Key References

- Magic ETL: Visual dataflow designer in Domo
- Tile types: Filter, Join, Group By, Formula, Script, JSON Expand
- Scripting: Python (pandas), R (dplyr)
- Data science tiles: Classification, Regression, Clustering, Forecasting
- MySQL DataFlow: SQL-based transformation (JSON injection pattern)
- Scheduling: Manual, Cron, Triggered, Chained
- Column rules: No spaces/special chars in MySQL DataFlows

## Examples

```bash
# Create a sales pipeline with join and aggregation
/domo/magic-etl design --name "Sales Summary" --tiles "join,group-by,formula"

# Add Python scripting for custom ML scoring
/domo/magic-etl script --dataflow "Lead Scoring" --lang python

# Expand nested JSON API responses
/domo/magic-etl json-expand --dataflow "API Ingest" --column "response_body" --path "$.data[*]"
```
