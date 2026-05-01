---
name: domo/appdb-manage
description: >
  Create, configure, and manage Domo AppDB collections. Handles document CRUD,
  security filters, permissions, sync configuration, export/import, and schema
  design with document-level access control.
  Triggers on: "appdb", "app database", "collection", "domo datastore", "document filter"
---

# /domo/appdb-manage

> Manage AppDB collections with document CRUD, security filters, and permission configuration.

## Purpose

AppDB is Domo's document database for custom apps. This skill handles the full lifecycle: creating collections, defining schemas, managing documents, configuring security filters (document-level and collection-level), enabling sync, and performing exports/imports. Ensures proper access control using Domo's filter wildcards.

## Usage

```bash
# Create a new collection
/domo/appdb-manage create --name "comments" --schema schema.json

# Configure security filter
/domo/appdb-manage filter --collection comments --type document --apply-on READ

# Export collection data
/domo/appdb-manage export --collection comments --format json
```

## Process

### Step 1: Collection Management

**Create Collection:**
```
POST /domo/datastores/v1/collections
Body: { "name": "collection-name", "schema": {...}, "syncEnabled": false }
```

**List Collections:**
```
GET /domo/datastores/v1/collections
```

**Delete Collection:**
```
DELETE /domo/datastores/v1/collections/{collectionName}
```

### Step 2: Document CRUD

| Operation | Method | Endpoint |
|-----------|--------|----------|
| Create | POST | `/domo/datastores/v1/collections/{name}/documents` |
| Read | GET | `/domo/datastores/v1/collections/{name}/documents/{id}` |
| Update | PUT | `/domo/datastores/v1/collections/{name}/documents/{id}` |
| Delete | DELETE | `/domo/datastores/v1/collections/{name}/documents/{id}` |
| Query | POST | `/domo/datastores/v1/collections/{name}/documents/query` |
| Bulk | POST | `/domo/datastores/v1/collections/{name}/documents/bulk` |

### Step 3: Security Filters (Document-Level)

Document-level filters restrict which documents a user can access. Configure in `manifest.json`:

```json
{
  "collections": {
    "comments": {
      "schema": { "owner_id": "string", "content": "string" },
      "documents": {
        "filters": [
          {
            "applyOn": ["READ", "UPDATE", "DELETE"],
            "applyTo": { "owner_id": "%userId%" }
          }
        ]
      }
    }
  }
}
```

**Filter Wildcards:**
- `%userId%` — Current user's ID
- `%groupIds%` — Array of current user's group IDs
- `limitToOwner: true` — Shorthand for owner-only access

**`applyOn` Values:** `READ`, `UPDATE`, `DELETE` (array of operations to filter)

**`applyTo` Structure:** Field-to-wildcard mapping that determines which documents match.

### Step 4: Collection-Level Permissions

Grant broader access at the collection level:
- **Manage AppDB** permission — Full CRUD on all collections (admin fallback).
- Per-collection grants for specific users/groups.

### Step 5: Sync Configuration

Enable dataset sync to mirror AppDB data as a Domo DataSet:
```json
{ "syncEnabled": true }
```
When enabled, AppDB data is periodically synced to a queryable dataset for cards/ETL.

### Step 6: Export/Import

**Manual Export:**
```
GET /domo/datastores/v1/collections/{name}/export
```
Note: Returns 423 (Locked) if another export is in progress.

**Include Related Collections:**
```
GET /domo/datastores/v1/collections/{name}/export?includeRelatedCollections=true
```

## Key References

- AppDB API base: `/domo/datastores/v1/collections`
- Security filter wildcards: `%userId%`, `%groupIds%`
- `applyOn`: `["READ", "UPDATE", "DELETE"]`
- `limitToOwner`: boolean shorthand for owner-only
- `syncEnabled`: mirrors data to a Domo DataSet
- Export lock: HTTP 423 if concurrent export attempted
- `@domoinc/toolkit` `AppDBClient` (Collections + Documents)

## Examples

```bash
# Create a comments collection with owner-based security
/domo/appdb-manage create --name comments --filter-owner

# Query documents with pagination
/domo/appdb-manage query --collection tasks --limit 50 --offset 0

# Enable sync for reporting
/domo/appdb-manage sync --collection orders --enable
```
