---
name: domo/workflow-automate
description: >
  Create and trigger Domo Workflows programmatically. Covers workflow design,
  start messages, input parameter types, status polling, and integration with
  apps and external systems via the Workflows Product API.
  Triggers on: "workflow", "automate", "domo workflow", "trigger workflow", "process automation"
---

# /domo/workflow-automate

> Create, trigger, and manage Domo Workflows via API for process automation.

## Purpose

Domo Workflows enables low-code process automation inside Domo. This skill covers programmatically starting workflows, passing input parameters, polling execution status, integrating workflows with custom apps, triggering from external systems, and designing workflow logic with Code Engine steps.

## Usage

```bash
# Start a workflow
/domo/workflow-automate start --model-id "abc-123" --data '{"param1": "value"}'

# Check workflow status
/domo/workflow-automate status --instance-id "xyz-789"

# Design workflow with Code Engine step
/domo/workflow-automate design --name "Order Processor" --steps "validate,process,notify"
```

## Process

### Step 1: Workflow API Authentication
Workflows Product API requires `X-DOMO-Developer-Token`:
```
Base URL: https://{instance}.domo.com/api/workflow/v1/
Header: X-DOMO-Developer-Token: {your_token}
```

Note: These APIs are CORS-restricted — call server-side only (Code Engine, Jupyter, external scripts).

### Step 2: Start a Workflow

```
POST /api/workflow/v1/instances/message
Body: {
  "messageName": "Start {WorkflowName}",
  "version": "1.1.0",
  "modelId": "a8afdc89-9491-4ee4-b7c3-b9e9b86c0138",
  "data": {
    "parameter1": 13,
    "parameter2": 7
  }
}
```

**Response (200):**
```json
{
  "id": "2052e10a-d142-4391-a731-2be1ab1c0188",
  "modelId": "a8afdc89-9491-4ee4-b7c3-b9e9b86c0138",
  "modelName": "AddTwoNumbers",
  "modelVersion": "1.1.0",
  "createdBy": "8811501",
  "createdOn": "2023-11-15T15:28:57.479Z",
  "status": null
}
```

Status values: `null` (not started yet), `IN_PROGRESS`, `CANCELED`, `COMPLETED`

### Step 3: Input Parameter Types
The `data` object must match the workflow's defined input types:

| Type | Example | Notes |
|------|---------|-------|
| `boolean` | `true` / `false` | |
| `date` | `"2024-01-15"` | ISO date format |
| `dateTime` | `"2024-01-15T10:00:00Z"` | ISO datetime |
| `decimal` | `3.14` | Floating-point |
| `duration` | `"PT1H30M"` | ISO 8601 duration |
| `number` | `42` | Integer |
| `object` | `{ "nested": "value" }` | Nested structures |
| `person` | `12345` | Domo user ID |
| `dataset` | `"ds-abc-123"` | Dataset ID |
| `group` | `67890` | Group ID |
| `text` | `"hello"` | String |
| `time` | `"14:30:00"` | Time only |

Lists of any type are also supported.

### Step 4: Triggering from Custom Apps

**Using App Framework Workflows API:**
```javascript
import { WorkflowClient } from '@domoinc/toolkit';

await WorkflowClient.start({
  modelId: 'workflow-model-id',
  messageName: 'Start ProcessOrder',
  version: '1.0.0',
  data: { orderId: 'ORD-123', amount: 99.99 }
});
```

**Using domo.js:**
```javascript
await domo.post('/domo/workflow/v1/instances/message', {
  messageName: 'Start ProcessOrder',
  version: '1.0.0',
  modelId: 'model-id',
  data: { orderId: 'ORD-123' }
});
```

### Step 5: Triggering from External Systems

From outside Domo (scripts, Jupyter, other services):
```bash
curl -X POST "https://your-instance.domo.com/api/workflow/v1/instances/message" \
  -H "X-DOMO-Developer-Token: YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "messageName": "Start MyWorkflow",
    "version": "1.0.0",
    "modelId": "model-uuid",
    "data": { "input1": "value1" }
  }'
```

### Step 6: Cross-Instance Workflows
Start workflows in remote Domo instances:
- Use the remote instance's Product API token.
- Target the remote instance URL.
- Useful for multi-tenant or federated architectures.
- Code Engine package: "Start Workflow in Remote Instance"

### Step 7: Workflow Design Patterns
- **Sequential**: Step A → Step B → Step C
- **Conditional**: If/else branching based on data
- **Parallel**: Multiple steps running simultaneously
- **Loop**: Repeat steps for list items
- **Human-in-the-loop**: Wait for user approval (Task Center)
- **Error handling**: Catch and retry failed steps

## Key References

- Workflows API: `POST /api/workflow/v1/instances/message`
- Auth: `X-DOMO-Developer-Token` header (server-side only, CORS restricted)
- Request schema: `messageName`, `version`, `modelId`, `data`
- Status values: `null`, `IN_PROGRESS`, `CANCELED`, `COMPLETED`
- Input types: boolean, date, dateTime, decimal, duration, number, object, person, dataset, group, text, time
- App invocation: `@domoinc/toolkit` WorkflowClient or `domo.js`
- Cross-instance: Remote instance token + URL

## Examples

```bash
# Start a data processing workflow with parameters
/domo/workflow-automate start --name "ETL Refresh" --data '{"dataset": "ds-123", "mode": "full"}'

# Poll until completion
/domo/workflow-automate wait --instance-id "inst-456" --timeout 300

# Trigger from Jupyter notebook
/domo/workflow-automate jupyter --model-id "model-789" --data '{"report_date": "2024-01-15"}'
```
