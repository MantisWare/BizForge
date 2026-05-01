---
name: domo/connector-build
description: >
  Design and build custom Domo connectors for data ingestion and writeback.
  Covers the connector IDE, authentication schemes, transport configuration,
  data parsing, publishing, and federated query setup.
  Triggers on: "connector", "custom connector", "data source", "writeback", "federated query"
---

# /domo/connector-build

> Build custom Domo connectors for data ingestion and writeback with full lifecycle management.

## Purpose

Create custom connectors that bring external data into Domo or write Domo data back to external systems. Covers the Connector IDE development environment, authentication configuration (OAuth2, API key, basic), transport setup, response parsing, error handling, rate limiting, and publishing to the Domo Appstore.

## Usage

```bash
# Create a new ingest connector
/domo/connector-build create --name "CRM Sync" --auth oauth2

# Create a writeback connector
/domo/connector-build create --name "S3 Export" --type writeback --auth api-key

# Publish connector to Appstore
/domo/connector-build publish --connector-id C123
```

## Process

### Step 1: Connector Type Selection

| Type | Direction | Purpose |
|------|-----------|---------|
| Ingest | External → Domo | Pull data from APIs/databases into Domo DataSets |
| Writeback | Domo → External | Push Domo data to external systems |
| Federated | Bidirectional | Query external sources in real-time without import |

### Step 2: Authentication Configuration

**OAuth 2.0:**
```json
{
  "authType": "oauth2",
  "authorizationUrl": "https://api.example.com/oauth/authorize",
  "tokenUrl": "https://api.example.com/oauth/token",
  "scopes": ["read", "write"],
  "clientId": "{{CLIENT_ID}}",
  "clientSecret": "{{CLIENT_SECRET}}"
}
```

**API Key:**
```json
{
  "authType": "api_key",
  "keyLocation": "header",
  "keyName": "X-API-Key"
}
```

**Basic Auth:**
```json
{
  "authType": "basic",
  "usernameField": "username",
  "passwordField": "password"
}
```

### Step 3: Transport Configuration
Define how the connector communicates with external systems:
- **HTTP/REST**: Configure base URL, headers, pagination.
- **SOAP**: Define WSDL endpoint and operations.
- **Database**: Configure JDBC/ODBC connection strings.
- **File**: Configure FTP/SFTP/S3 file access.

### Step 4: Data Parsing
Configure how responses are parsed into Domo columns:
1. Define the response schema (JSON path, XML path, CSV columns).
2. Map source fields to Domo column types (STRING, LONG, DOUBLE, DATE, DATETIME).
3. Handle nested/array data with flattening rules.
4. Configure incremental vs full-replace update modes.

### Step 5: Error Handling and Rate Limiting
- Implement retry logic for transient failures (429, 503).
- Respect API rate limits with configurable backoff.
- Log errors with context for debugging.
- Handle pagination exhaustion gracefully.

### Step 6: Connector IDE Development
The Connector IDE provides:
- Code editor for connector logic.
- Test execution against real credentials.
- Schema preview and validation.
- Version management.

### Step 7: On-Premises Data (Workbench)
For data behind firewalls:
- Use Domo Workbench (Windows agent) for scheduled data push.
- Configure connection to local databases/files.
- Schedule sync frequency.
- No inbound firewall rules required.

### Step 8: Federated Queries
Query external databases in real-time:
- Configure federated adapter connection.
- Define query patterns and materialization rules.
- Set cache TTL for performance.
- Supports SQL-compatible external sources.

### Step 9: Publishing
- Test connector with multiple accounts/configurations.
- Document required credentials and permissions.
- Submit to Domo Appstore via Partner portal.
- Include usage examples and troubleshooting guide.

## Key References

- Connector IDE: In-product development environment
- Auth types: OAuth2, API Key, Basic, None
- Data types: STRING, LONG, DOUBLE, DATE, DATETIME
- Update modes: REPLACE, APPEND
- Workbench: On-premises data agent (Windows)
- Federated queries: Real-time external database access
- Writeback: Domo → external system data push
- Rate limiting: Configurable retry/backoff patterns

## Examples

```bash
# Build a REST API connector with OAuth2 and pagination
/domo/connector-build create --name "Shopify Orders" --auth oauth2 --pagination cursor

# Build a writeback connector to S3
/domo/connector-build create --name "S3 Writeback" --type writeback --transport s3

# Configure federated query to Snowflake
/domo/connector-build federated --source snowflake --cache-ttl 300
```
