---
name: domo/instance-admin
description: >
  Full Domo instance administration — authenticate via OAuth or Developer Token,
  then manage users/groups, create and import datasets, configure AppDB collections,
  set PDP policies, manage pages/cards, audit activity logs, configure SSO, and
  govern content across a client Domo instance.
  Triggers on: "domo admin", "instance admin", "domo manage", "create users domo", "domo groups", "domo permissions", "administer domo", "domo setup", "domo configure"
required_integrations:
  - provider: domo
    config_keys:
      - key: instance_url
        label: Instance URL
        is_secret: false
        required: true
      - key: client_id
        label: OAuth Client ID
        is_secret: true
        required: true
      - key: client_secret
        label: OAuth Client Secret
        is_secret: true
        required: true
      - key: developer_token
        label: Developer Token
        is_secret: true
        required: false
    scopes: [data, user, dashboard, account, audit]
required_tools:
  - bash
  - web-search
---

# /domo/instance-admin

> Full administration of a client's Domo instance — users, groups, datasets, AppDB, pages, PDP, content, audit, and security.

## Purpose

This skill enables an agent to log into a client's Domo instance and perform all administrative tasks programmatically: create and manage users and groups, build and import datasets, configure AppDB collections, set up PDP (Personalized Data Permissions), manage pages and cards, audit activity, configure SSO, and govern content. The agent becomes a virtual Domo administrator capable of standing up and maintaining an entire instance.

## Prerequisites

Before performing any administration, the agent must authenticate:

1. **Platform (OAuth) API** — preferred for scoped operations:
   - Create an OAuth client at Admin > Security > OAuth
   - Available scopes: `data`, `user`, `dashboard`, `account`, `audit`
   - Generate token: `POST https://api.domo.com/oauth/token` with `grant_type=client_credentials`
   
2. **Product API** — for full admin parity:
   - Generate Developer Token at Admin > Security > Access Tokens
   - Use header: `X-DOMO-Developer-Token: {token}`
   - Has full permissions of the generating user — handle with care

3. **Python SDK (pydomo):**
   ```python
   from pydomo import Domo
   domo = Domo(client_id, client_secret, api_host='api.domo.com')
   ```

4. **Java SDK (domo-java-sdk):**
   ```java
   DomoClient client = DomoClient.create(clientId, clientSecret);
   ```

## Process

### Step 1: User Management

**Create User:**
```http
POST https://api.domo.com/v1/users?sendInvite=true
Authorization: bearer {access_token}
Content-Type: application/json

{
  "name": "Jane Smith",
  "email": "jane@company.com",
  "role": "Participant",
  "title": "Data Analyst",
  "phone": "888-555-0123",
  "location": "Salt Lake City",
  "timezone": "America/Denver"
}
```

**Roles:** Admin, Privileged, Editor, Participant, Social

**List Users:**
```http
GET https://api.domo.com/v1/users?limit=50&offset=0
```

**Update User (change role, title, etc.):**
```http
PUT https://api.domo.com/v1/users/{userId}
Body: { "role": "Editor", "title": "Senior Analyst" }
```

**Delete User:**
```http
DELETE https://api.domo.com/v1/users/{userId}
```

**User fields:** name, email, alternateEmail, role, title, phone, location, timezone, locale, employeeNumber

### Step 2: Group Management

**Create Group:**
```http
POST https://api.domo.com/v1/groups
Body: { "name": "Marketing Team" }
```
Response includes `id` — store for subsequent operations.

**Add User to Group:**
```http
PUT https://api.domo.com/v1/groups/{groupId}/users/{userId}
```

**Remove User from Group:**
```http
DELETE https://api.domo.com/v1/groups/{groupId}/users/{userId}
```

**List Group Members:**
```http
GET https://api.domo.com/v1/groups/{groupId}/users
```

**List All Groups:**
```http
GET https://api.domo.com/v1/groups?limit=50&offset=0
```

**Delete Group:**
```http
DELETE https://api.domo.com/v1/groups/{groupId}
```

Groups are used for PDP policies, page sharing, Buzz conversations, and permission management.

### Step 3: Dataset Creation & Import

**Create Dataset with Schema:**
```http
POST https://api.domo.com/v1/datasets
Body: {
  "name": "Sales Q4",
  "description": "Fourth quarter sales data",
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

**Column types:** STRING, LONG, DOUBLE, DATE (`yyyy-MM-dd`), DATETIME (`yyyy-MM-dd'T'HH:mm:ss`)

**Import CSV Data (small datasets):**
```http
PUT https://api.domo.com/v1/datasets/{datasetId}/data
Content-Type: text/csv
Body: RFC-4180 formatted CSV
```

**Stream API (large datasets, 1M+ rows):**
```
1. POST /v1/streams              — create stream
2. POST /v1/streams/{id}/executions   — create execution
3. PUT  /v1/streams/{id}/executions/{execId}/part/{partId}  — upload gzip parts
4. PUT  /v1/streams/{id}/executions/{execId}/commit         — commit (required!)
```

**List Datasets:**
```http
GET https://api.domo.com/v1/datasets?limit=50&offset=0
```

**Export Data:**
```http
GET https://api.domo.com/v1/datasets/{datasetId}/data?includeHeader=true
```

**Delete Dataset:**
```http
DELETE https://api.domo.com/v1/datasets/{datasetId}
```

### Step 4: AppDB Collection Management

**Create Collection (via Product API or Code Engine):**
```http
POST https://{instance}.domo.com/api/datastores/v1/collections
X-DOMO-Developer-Token: {token}
Body: {
  "name": "UserPreferences",
  "schema": {
    "columns": [
      { "name": "userId", "type": "STRING" },
      { "name": "theme", "type": "STRING" }
    ]
  },
  "syncEnabled": false
}
```

**IMPORTANT:** Always use `STRING` type for all AppDB columns — other types are unreliable.

**List Collections:**
```http
GET /api/datastores/v1/collections
```

**Create Document:**
```http
POST /api/datastores/v1/collections/{name}/documents
Body: { "content": { "userId": "123", "theme": "dark" } }
```

**Query Documents:**
```http
POST /api/datastores/v1/collections/{name}/documents/query
Body: { "content.userId": { "$eq": "123" } }
```

**Bulk Insert:**
```http
POST /api/datastores/v1/collections/{name}/documents/bulk
Body: [{ "content": {...} }, { "content": {...} }]
```

**Configure Security Filters (in manifest or via API):**
```json
{
  "documents": {
    "filters": [{
      "applyOn": ["READ", "UPDATE", "DELETE"],
      "applyTo": { "owner": "%userId%" }
    }]
  }
}
```

### Step 5: PDP (Personalized Data Permissions)

**Create PDP Policy:**
```http
POST https://api.domo.com/v1/datasets/{datasetId}/policies
Body: {
  "name": "West Region Only",
  "type": "user",
  "users": [12345, 67890],
  "filters": [{
    "column": "region",
    "values": ["West"],
    "operator": "EQUALS"
  }]
}
```

**Policy types:** user (specific users), group (group members), system (all non-admins)

**List Policies:**
```http
GET https://api.domo.com/v1/datasets/{datasetId}/policies
```

**Update Policy:**
```http
PUT https://api.domo.com/v1/datasets/{datasetId}/policies/{policyId}
Body: { "name": "Updated Policy", "filters": [...] }
```

**Delete Policy:**
```http
DELETE https://api.domo.com/v1/datasets/{datasetId}/policies/{policyId}
```

**Best practices:**
- Apply PDP at SOURCE dataset, not derived/ETL datasets
- Use groups over individual users for maintainability
- Test with "View As" feature in Domo UI
- All users see ALL data by default until first policy is created
- After first policy: users see NOTHING unless a policy grants access

### Step 6: Page & Content Management

**Create Page (Dashboard):**
```http
POST https://api.domo.com/v1/pages
Body: {
  "name": "Executive Dashboard",
  "parentId": 23,
  "locked": true,
  "cardIds": [12, 2535, 233],
  "visibility": {
    "userIds": [793, 20],
    "groupIds": [32, 25]
  }
}
```

**Create Page Collection (section):**
```http
POST https://api.domo.com/v1/pages/{pageId}/collections
Body: { "title": "Revenue Metrics", "cardIds": [2535, 233] }
```

**Update Page (share with new users/groups):**
```http
PUT https://api.domo.com/v1/pages/{pageId}
Body: {
  "visibility": { "userIds": [993, 19234], "groupIds": [2, 28] }
}
```

**List Pages:**
```http
GET https://api.domo.com/v1/pages?limit=50&offset=0
```

### Step 7: Activity Log & Audit

**Query Activity Logs:**
```http
GET https://api.domo.com/v1/audit?start={epochMs}&end={epochMs}&limit=100
```

**Key event types:**
- `VIEWED` — content accessed (page, card)
- `CREATED` / `DELETED` — entity lifecycle
- `EXPORTED` — data export events
- `LOGIN` / `FAILED_LOGIN` — authentication events
- `PERMISSION_CHANGE` — access modifications
- `PDP_POLICY_CREATED` / `PDP_POLICY_UPDATED`

**Response fields:** actionType, actorId, actorName, objectType, objectName, ipAddress, device, time

**Use cases:**
- Security auditing and compliance (SOX, HIPAA, GDPR)
- Track data access patterns and unusual activity
- Ship logs to SIEM (Sentinel, Splunk) via webhook

### Step 8: SSO Configuration

**Supported protocols:** SAML 2.0, OAuth 2.0 / OpenID Connect

**Supported IdPs:** Okta, Azure AD, PingIdentity, Google, OneLogin, ADFS

**Configuration steps:**
1. Enable SSO in Admin > Security > SSO
2. Configure IdP metadata (entity ID, SSO URL, certificate)
3. Map IdP attributes to Domo user fields
4. Test with a pilot group before full rollout
5. Configure JIT (Just-In-Time) auto-provisioning if desired
6. Whitelist `*.domoapps.*.domo.com` in IdP for embedded app scenarios

### Step 9: Security Controls

- **IP whitelisting:** Restrict instance access by network
- **Session management:** Configure timeout policies
- **Password policies:** Complexity, rotation, MFA enforcement
- **API token governance:** Regular rotation, admin revocation
- **Custom App domain whitelisting:** Admin > Network Security > Custom Apps authorized domains
- **SIEM integration:** Ship activity logs to external SIEM via webhooks

## MCP Tools Available

When MCP servers are configured, the following tools are available for automated administration:

| Server | Tools | Admin Capabilities |
|--------|-------|--------------------|
| domo-users | 6 | User CRUD, list, search, role management |
| domo-datasets | 16 | Dataset CRUD, schema, SQL query, CSV import, lineage |
| domo-appdb | 12 | Collection and document CRUD, bulk insert, security |
| domo-pages | 27 | Page/card CRUD, Beast Modes, layout, app cards |
| domo-codeengine | 11 | Serverless function package lifecycle |
| domo-publish | 6 | App design listing, manifest validation, publish |
| domo-search | 2 | Cross-entity search |

## Key References

- User API: `GET/POST/PUT/DELETE /v1/users`
- Group API: `GET/POST/PUT/DELETE /v1/groups`
- Dataset API: `GET/POST/PUT/DELETE /v1/datasets`
- Stream API: `/v1/streams` (for large data)
- Page API: `GET/POST/PUT/DELETE /v1/pages`
- PDP API: `/v1/datasets/{id}/policies`
- Activity Log API: `GET /v1/audit`
- AppDB API: `/api/datastores/v1/collections` (Product API)
- OAuth endpoint: `POST https://api.domo.com/oauth/token`
- Product header: `X-DOMO-Developer-Token`
- Scopes: data, user, dashboard, account, audit
- SDKs: `pydomo` (Python), `domo-java-sdk` (Java)
- Roles: Admin, Privileged, Editor, Participant, Social

## Examples

```bash
# Authenticate and provision a new team
/domo/instance-admin auth --client-id CID --client-secret SECRET --scopes "data,user,dashboard"
/domo/instance-admin users --action create --name "Jane Smith" --email "jane@co.com" --role Editor
/domo/instance-admin groups --action create --name "Analytics Team"
/domo/instance-admin groups --action add-user --group "Analytics Team" --user "jane@co.com"

# Create dataset and apply PDP
/domo/instance-admin datasets --action create --name "Sales" --columns "region:STRING,amount:DOUBLE"
/domo/instance-admin datasets --action import --id DS123 --file sales.csv
/domo/instance-admin pdp --action create --dataset DS123 --name "West Only" --column region --values "West"

# Create dashboard and share
/domo/instance-admin pages --action create --name "Executive Dashboard" --cards 12,233
/domo/instance-admin pages --action share --id 3242 --groups "Analytics Team"

# Audit recent activity
/domo/instance-admin audit --days 7 --event-type LOGIN
```
