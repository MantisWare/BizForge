---
name: data-modeling/erd-parse
description: >
  Parse Entity-Relationship Diagrams from multiple formats (DBML, SQL DDL,
  Prisma schema, mermaid erDiagram, dbdiagram.io export, or image) into a
  structured entity graph with relationships and cardinalities. The parsed
  graph becomes the foundation for documentation, task generation, and data
  pipeline design.
  Triggers on: "parse erd", "entity relationship", "database schema", "dbml",
  "sql schema", "data model", "er diagram", "erd"
required_integrations: []
required_tools: []
---

# /erd-parse

> Parse an ERD into a structured entity graph.

## Purpose

Convert any representation of a data model — text-based (DBML, SQL, Prisma,
mermaid) or visual (PNG, SVG, PDF) — into a normalized JSON structure that
downstream consumers (GenerateIssuesModal, GoalDecomposer, document generators)
can reason about. This is the entry point for "give me an ERD, build the app".

## Supported Input Formats

| Format | Detection | Parser |
|--------|-----------|--------|
| DBML | Starts with `Table` or `Ref:` | `@dbml/core` |
| SQL DDL | Contains `CREATE TABLE` | Regex-based DDL parser |
| Prisma | Contains `model` + `@id` | Regex mapper |
| Mermaid erDiagram | Starts with `erDiagram` | Line-by-line parser |
| dbdiagram.io export | Same as DBML | `@dbml/core` |
| Image (PNG/SVG/PDF) | Binary/base64 MIME check | Multimodal LLM vision |

## Output Schema

```typescript
interface ErdGraph {
  entities: Entity[];
  relationships: Relationship[];
  notes: string[];
}

interface Entity {
  name: string;
  columns: Column[];
  indexes: Index[];
}

interface Column {
  name: string;
  type: string;
  nullable: boolean;
  pk: boolean;
  fk: { table: string; column: string } | null;
  default: string | null;
  unique: boolean;
}

interface Index {
  name: string | null;
  columns: string[];
  unique: boolean;
}

interface Relationship {
  from: string;
  to: string;
  cardinality: "one-to-one" | "one-to-many" | "many-to-many";
  name: string | null;
  from_column: string | null;
  to_column: string | null;
}
```

## Usage

```bash
# Parse DBML text
/erd-parse --format dbml --input "Table users { id int [pk] ... }"

# Parse from file path
/erd-parse --file ./schema.sql

# Parse from image (requires multimodal model)
/erd-parse --image ./erd-diagram.png

# Auto-detect format
/erd-parse --input "<paste text here>"
```

## Arguments

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--format` | enum | auto-detect | `dbml`, `sql`, `prisma`, `mermaid`, `image` |
| `--input` | string | — | Raw text content to parse |
| `--file` | path | — | Path to file containing the schema |
| `--image` | path | — | Path to ERD image for vision parsing |
| `--output` | enum | `json` | Output format: `json`, `mermaid`, `markdown` |

## Workflow

### Step 1: Format Detection

If `--format` is not specified, auto-detect by scanning the input:

1. Contains `CREATE TABLE` (case-insensitive) → SQL DDL
2. Starts with `Table ` or contains `Ref:` → DBML
3. Contains `model ` + `@id` or `@relation` → Prisma
4. Starts with `erDiagram` → Mermaid
5. Binary content or image MIME type → Image (delegate to vision)

### Step 2: Parse

Run the format-specific parser. Each parser normalizes into the `ErdGraph`
schema above.

### Step 3: Validate

- Check for duplicate entity names
- Verify FK references point to existing entities
- Warn on entities with no PK
- Validate cardinality consistency

### Step 4: Store

Save the parsed graph as a `Document` with:
- `format: "erd-graph"`
- `content: JSON.stringify(erdGraph)`
- `project_id` from the active project context

Also save the raw source as a companion document with `format: "erd-source"`.

## Downstream Integration

### GenerateIssuesModal
When building the prompt, detect documents with `format: "erd-graph"` and
prepend a structured block:

```
## Data Model (from ERD)

### Entities
- users (id PK, email, name, role, created_at)
- orders (id PK, user_id FK→users, total, status, created_at)
...

### Relationships
- users 1:N orders
- orders N:M products (via order_items)
...

Propose issues for: CRUD per entity, validation rules, API endpoints,
AppDB collections (if Domo), dataset schemas, ETL loads, UI cards, QA matrix.
```

### GoalDecomposer
Same entity-aware prompt injection when the goal's project has ERD documents.

## Dependencies

- `@dbml/core` — DBML parser (npm, for desktop/frontend parsing)
- Multimodal LLM — for image-based ERD parsing (Phase 1 attachments)
