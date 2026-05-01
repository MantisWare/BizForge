---
name: domo/data-science
description: >
  Leverage Domo's data science capabilities including Jupyter workspaces,
  AutoML, AI services, scripting tiles, and accelerator patterns for advanced
  analytics and machine learning within the Domo platform.
  Triggers on: "jupyter", "data science", "automl", "ai service", "machine learning", "domo ai"
---

# /domo/data-science

> Leverage Domo's data science stack: Jupyter, AutoML, AI services, and scripting tiles.

## Purpose

Domo provides an integrated data science environment for building, training, and deploying ML models alongside business data. This skill covers Jupyter workspace setup, AutoML for no-code modeling, AI Service Layer for LLM integration, scripting tiles in Magic ETL, and accelerator patterns for common analytics workflows.

## Usage

```bash
# Create a Jupyter workspace
/domo/data-science jupyter --create --lang python --dataset "Sales History"

# Run AutoML on a dataset
/domo/data-science automl --dataset "Churn Data" --target "churned" --type classification

# Invoke AI service from app
/domo/data-science ai-service --model "summarize" --input "Quarterly report text..."
```

## Process

### Step 1: Jupyter Workspaces

**Setup:**
1. Create a Jupyter workspace in Domo (Data Science > Jupyter).
2. Select kernel: Python 3 or R.
3. Attach input datasets (available as DataFrames).
4. Write analysis / model training code.
5. Output results as a new Domo dataset.

**Python Example:**
```python
import pandas as pd
from domo import read_dataframe, write_dataframe

# Read input dataset
df = read_dataframe('Sales History')

# Transform / analyze
df['growth_rate'] = df['revenue'].pct_change()
monthly = df.groupby('month').agg({'revenue': 'sum', 'growth_rate': 'mean'})

# Write output dataset
write_dataframe(monthly, 'Monthly Sales Summary')
```

**R Example:**
```r
library(dplyr)

# Input dataset available as 'df'
result <- df %>%
  group_by(month) %>%
  summarise(
    total_revenue = sum(revenue),
    avg_growth = mean(growth_rate, na.rm = TRUE)
  )

# Output written automatically
```

**Key Features:**
- Persistent workspaces with package installations.
- Scheduled execution (like ETL dataflows).
- Access to Domo APIs via Product token.
- GPU instances available for deep learning.

### Step 2: AutoML

Domo's AutoML automates model selection and training:

1. **Select dataset** with features and target column.
2. **Choose problem type**: Classification, Regression, Time Series Forecasting.
3. **Configure**: Train/test split, feature exclusions, time column.
4. **Run**: Domo trains multiple models and ranks by performance.
5. **Deploy**: Best model is deployed as a scoring pipeline.
6. **Score**: New data is automatically scored on schedule.

**Supported Algorithms:**
- Classification: Logistic Regression, Random Forest, XGBoost, Neural Network
- Regression: Linear, Ridge, Lasso, XGBoost, Neural Network
- Forecasting: ARIMA, Prophet, LSTM

### Step 3: AI Service Layer

The AI Service Layer provides LLM access within Domo apps:

**From Custom App (`@domoinc/toolkit`):**
```javascript
import { AIClient } from '@domoinc/toolkit';

const response = await AIClient.generate({
  model: 'domo-ai',
  prompt: 'Summarize the following sales data...',
  maxTokens: 500
});
```

**From App Framework:**
```javascript
const result = await domo.post('/domo/ai/v1/generate', {
  prompt: 'Analyze this trend...',
  context: datasetRows
});
```

**Use Cases:**
- Natural language querying of datasets.
- Automated report summarization.
- Anomaly explanation in natural language.
- Content generation from data patterns.

### Step 4: Scripting Tiles (Magic ETL)

Embed Python/R code directly in ETL pipelines:

**Python Scripting Tile:**
```python
# Input: 'df' DataFrame with all upstream columns
from sklearn.preprocessing import StandardScaler

scaler = StandardScaler()
df[['revenue', 'units']] = scaler.fit_transform(df[['revenue', 'units']])

# Scored output
df['anomaly_score'] = isolation_forest.predict(df[['revenue', 'units']])
```

**When to use scripting tiles vs Jupyter:**
- Scripting tiles: Simple inline transforms within ETL pipelines.
- Jupyter: Complex analysis, model training, exploratory work.

### Step 5: Data Science Accelerators

Pre-built analytical patterns:
- **Customer Churn**: Predict at-risk customers.
- **Demand Forecasting**: Predict future demand from history.
- **Anomaly Detection**: Flag unusual data points.
- **Sentiment Analysis**: Analyze text sentiment.
- **Market Basket**: Association rule mining.
- **Customer Segmentation**: RFM and clustering.

Each accelerator provides:
- Pre-configured ETL pipeline.
- Required dataset schema documentation.
- Visualization templates (cards/dashboards).
- Tuning parameters for domain customization.

### Step 6: Model Deployment Pipeline

End-to-end ML workflow in Domo:
1. **Data prep**: Magic ETL cleans and features.
2. **Training**: Jupyter or AutoML trains model.
3. **Evaluation**: Compare metrics in Domo cards.
4. **Deployment**: Model outputs as a dataset (auto-scored).
5. **Monitoring**: Track drift with alerting.
6. **Retraining**: Scheduled Jupyter re-runs when drift detected.

## Key References

- Jupyter: Data Science > Jupyter Workspaces
- AutoML: No-code model training and deployment
- AI Service Layer: `/domo/ai/v1/generate` (app context)
- `@domoinc/toolkit` AIClient for LLM access
- Scripting tiles: Python/R in Magic ETL dataflows
- Accelerators: Pre-built ML patterns (churn, forecast, anomaly)
- Languages: Python (pandas, sklearn, tensorflow), R (dplyr, caret)
- Scheduling: Jupyter workspaces can run on schedule
- GPU: Available for deep learning workloads

## Examples

```bash
# Set up a churn prediction pipeline
/domo/data-science automl --dataset "Customer Activity" --target "churned" --type classification

# Create Jupyter workspace for exploratory analysis
/domo/data-science jupyter --create --attach "Sales,Inventory,Returns"

# Use AI service to explain anomalies
/domo/data-science ai-service --action explain --dataset "Revenue Anomalies"
```
