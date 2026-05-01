---
name: domo/code-engine
description: >
  Write and deploy Domo Code Engine functions (JavaScript/Python) that run
  server-side. Covers function creation, package management, invocation from
  apps and workflows, debugging, and versioning.
  Triggers on: "code engine", "serverless", "domo function", "server-side code", "code engine function"
---

# /domo/code-engine

> Write, deploy, and manage server-side Code Engine functions in Domo.

## Purpose

Code Engine provides serverless function execution inside Domo. This skill covers writing functions in JavaScript or Python, managing available packages, invoking functions from custom apps or workflows, handling errors, and managing function versions. Code Engine functions run server-side with access to Domo APIs.

## Usage

```bash
# Create a new Code Engine function
/domo/code-engine create --name "processOrder" --lang javascript

# Deploy function update
/domo/code-engine deploy --name "processOrder" --version 2

# Invoke from app context
/domo/code-engine invoke --name "processOrder" --data '{"orderId": 123}'
```

## Process

### Step 1: Function Creation
Create a new Code Engine function via the Domo UI or API:

**JavaScript function structure:**
```javascript
async function main(event) {
  const { data, environment } = event;
  // Access Domo APIs via environment
  // Process input data
  return { statusCode: 200, body: { result: "success" } };
}

module.exports = { main };
```

**Python function structure:**
```python
def main(event):
    data = event.get("data", {})
    environment = event.get("environment", {})
    # Process input
    return {"statusCode": 200, "body": {"result": "success"}}
```

### Step 2: Available Packages

**JavaScript libraries** available in Code Engine:
- Standard Node.js built-ins
- HTTP clients (axios, node-fetch)
- Data processing utilities
- Domo-specific helpers

**Python packages** available in Code Engine:
- Standard library modules
- requests
- pandas, numpy
- json, csv processing
- Domo-specific helpers

### Step 3: Invocation Patterns

**From a Custom App (App Framework):**
```javascript
import { CodeEngineClient } from '@domoinc/toolkit';

const result = await CodeEngineClient.run('functionName', {
  input: { key: 'value' }
});
```

**From a Workflow:**
Configure a Code Engine step in the workflow designer, passing workflow variables as input parameters.

**Via Product API (external):**
```
POST https://{instance}.domo.com/api/codeengine/v1/functions/{functionId}/execute
Headers: X-DOMO-Developer-Token: {token}
Body: { "input": { ... } }
```

### Step 4: Error Handling
- Functions must return a response object with `statusCode`.
- Unhandled exceptions return 500 with error details.
- Set timeouts appropriately (default varies by plan).
- Log errors for debugging via function logs.

```javascript
async function main(event) {
  try {
    const result = await processData(event.data);
    return { statusCode: 200, body: result };
  } catch (error) {
    return { statusCode: 500, body: { error: error.message } };
  }
}
```

### Step 5: Environment Variables
- Configure environment variables in the Code Engine UI.
- Access via `event.environment` object.
- Store secrets (API keys, tokens) as environment variables.
- Never hardcode credentials in function source.

### Step 6: Versioning and Deployment
- Each publish creates a new version.
- Roll back by activating a previous version.
- Test in development before publishing to production.
- Use naming conventions: `domain-action` (e.g., `orders-process`).

## Key References

- Code Engine API: `/api/codeengine/v1/functions`
- `@domoinc/toolkit` `CodeEngineClient` for app invocation
- Function signature: `main(event)` with `event.data`, `event.environment`
- Response format: `{ statusCode: number, body: object }`
- Invocation: from apps, workflows, or external via Product API
- Languages: JavaScript (Node.js), Python

## Examples

```bash
# Create a data transformation function
/domo/code-engine create --name "transform-sales" --lang python --trigger workflow

# Debug a failing function
/domo/code-engine debug --name "processOrder" --last-error

# List all deployed functions
/domo/code-engine list --status active
```
