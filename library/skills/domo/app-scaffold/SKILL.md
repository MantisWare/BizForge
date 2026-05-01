---
name: domo/app-scaffold
description: >
  Initialize and scaffold a new Domo custom app or DDX Brick. Generates
  manifest.json, configures dataset mappings, sets up proxy for local AppDB
  development, and selects appropriate starter kit.
  Triggers on: "domo app", "scaffold domo", "domo init", "new domo app", "create brick"
---

# /domo/app-scaffold

> Scaffold a new Domo custom app or DDX Brick with manifest, dataset wiring, and local dev configuration.

## Purpose

Create a fully configured Domo app project from scratch. Handles CLI authentication, project initialization, manifest schema generation, dataset alias mapping, AppDB proxy setup, and starter kit selection. Produces a project ready for `domo dev` local development.

## Usage

```bash
# Scaffold a new custom app with React starter
/domo/app-scaffold --type custom-app --starter react

# Scaffold a DDX Brick
/domo/app-scaffold --type brick --name "Sales Dashboard"

# Scaffold with AppDB collections pre-configured
/domo/app-scaffold --type custom-app --appdb collections.json
```

## Process

### Step 1: Authentication Check
Verify the developer is authenticated via `domo login`. If not authenticated:
1. Run `domo login` with instance credentials.
2. Confirm session token is valid.
3. Store credentials for subsequent CLI commands.

### Step 2: Project Initialization
Run `domo init` and configure based on type:

| Type | CLI Command | Result |
|------|-------------|--------|
| Custom App | `domo init` | Full App Framework project |
| DDX Brick | `domo init --template brick` | Lightweight brick project |

### Step 3: Manifest Configuration
Generate `manifest.json` with required fields:

```json
{
  "name": "App Name",
  "version": "1.0.0",
  "size": { "width": 4, "height": 4 },
  "mapping": [
    {
      "dataSetId": "alias-name",
      "alias": "Sales Data",
      "fields": []
    }
  ],
  "proxyId": "local-appdb-proxy-id"
}
```

Key configuration decisions:
- **size**: Grid units (1-12 width, 1-12 height) for card placement.
- **mapping**: Dataset aliases that wire to real datasets on publish.
- **proxyId**: Required for local AppDB development — obtain from instance.

### Step 4: Starter Kit Selection
Available starter kits:
- **React** — Create React App with `domo.js` pre-wired.
- **Vanilla JS** — Minimal HTML/JS/CSS with `domo.js`.
- **Angular** — Angular CLI project with Domo integration.
- **Vue** — Vue 3 project with Domo data layer.

### Step 5: Dataset Mapping
For each dataset the app needs:
1. Define an alias in `manifest.json` `mapping` array.
2. Specify required fields (column names) in the `fields` array.
3. Document the expected schema for downstream wiring.

### Step 6: AppDB Proxy Setup (if needed)
If the app uses AppDB:
1. Obtain `proxyId` from your Domo instance (AppDB > Collections > Settings).
2. Add `proxyId` to `manifest.json`.
3. Create initial collection schema definitions.
4. Verify local proxy connectivity with `domo dev`.

### Step 7: Local Development Launch
Start the development server:
```bash
domo dev
```
This proxies API calls through your authenticated session, enabling:
- Dataset queries via `/data/v1/{alias}`
- AppDB operations via `/domo/datastores/v1/collections`
- User/Group API access

## Key References

- Domo Apps CLI: `domo login`, `domo init`, `domo dev`, `domo publish`
- Manifest schema: `name`, `version`, `size`, `mapping`, `proxyId`
- Starter kits: React, Vanilla, Angular, Vue
- `@domoinc/toolkit` for AppDB/Data/Code Engine clients
- `domo.js` for data fetching (`domo.get`, `domo.post`)

## Examples

```bash
# Full scaffold for a React app with two datasets
/domo/app-scaffold --type custom-app --starter react --datasets "Sales,Inventory"

# Brick scaffold for a simple KPI tile
/domo/app-scaffold --type brick --name "Revenue KPI" --size 2x2

# App with AppDB and proxy configured
/domo/app-scaffold --type custom-app --starter react --appdb --proxy abc123
```
