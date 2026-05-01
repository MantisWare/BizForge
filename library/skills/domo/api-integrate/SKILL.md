---
name: domo/api-integrate
description: >
  Authenticate and interact with all three Domo API tiers: App Framework,
  Platform (OAuth), and Product APIs. Covers client creation, token management,
  scope selection, endpoint routing, and CORS considerations.
  Triggers on: "domo api", "api auth", "oauth domo", "developer token", "platform api", "product api"
---

# /domo/api-integrate

> Authenticate and interact with Domo's three API tiers for external integration.

## Purpose

Domo provides three distinct API layers, each with different authentication, scope, and use cases. This skill covers choosing the right API tier, creating OAuth clients, managing access tokens, selecting scopes, routing to correct endpoints, and handling CORS restrictions. Ensures secure, properly-scoped API access for any integration scenario.

## Usage

```bash
# Create an OAuth client with dataset scope
/domo/api-integrate client-create --name "ETL Pipeline" --scopes "data,user"

# Generate access token
/domo/api-integrate token --client-id CID123 --client-secret SECRET

# Make authenticated API call
/domo/api-integrate call --tier product --endpoint "/v1/datasets" --method GET
```

## Process

### Step 1: Choose API Tier

| Tier | Context | Auth Method | Best For |
|------|---------|-------------|----------|
| **App Framework** | Inside Domo apps | App Session Token (automatic) | Custom app development |
| **Platform (OAuth)** | External, scoped | OAuth client_id + secret → access_token | Automations, integrations |
| **Product** | External, full access | `X-DOMO-Developer-Token` | Full Domo UI parity |

**Decision tree:**
- Building a custom app? → **App Framework APIs**
- External script with specific scope? → **Platform APIs** (preferred)
- Need full UI-equivalent access? → **Product APIs** (use carefully)

### Step 2: App Framework Authentication
Authentication is handled automatically:
- `domo login` authenticates the CLI session.
- In-app, session tokens are inherited.
- Use `domo.js` (`domo.get`, `domo.post`) for data access.
- Use `@domoinc/toolkit` clients for structured API access.

**Available App Framework APIs:**
- AI Service Layer, AppDB, Code Engine, Data, Files, Groups, Task Center, User, Workflows

### Step 3: Platform (OAuth) Client Setup

**Create Client:**
1. Navigate to Admin > Security > OAuth (developer.domo.com).
2. Create a new client with selected scopes.
3. Store `client_id` and `client_secret` securely.

**Available Scopes:**
- `data` — DataSet CRUD, import/export
- `user` — User management
- `dashboard` — Page/card operations
- `account` — Data account management
- `audit` — Activity log access

**Generate Access Token:**
```
POST https://api.domo.com/oauth/token
Content-Type: application/x-www-form-urlencoded
Authorization: Basic {base64(client_id:client_secret)}
Body: grant_type=client_credentials&scope=data user
```

Response:
```json
{
  "access_token": "eyJ...",
  "token_type": "bearer",
  "expires_in": 3600,
  "scope": "data user"
}
```

Tokens expire and must be refreshed. This is a security feature.

### Step 4: Product API Authentication

**Generate Developer Token:**
1. Go to Admin > Security > Access Tokens in Domo.
2. Create a new token (full access as your user).
3. Store securely — this token has full permissions.

**Use in requests:**
```
GET https://{instance}.domo.com/api/content/v1/...
Headers: X-DOMO-Developer-Token: {your_token}
```

**Caution:** Product tokens have no scope limitation. They can do anything your user can do in the UI. Prefer Platform (OAuth) APIs when possible.

### Step 5: Endpoint Structure

**Platform API endpoints** (OAuth):
```
https://api.domo.com/v1/datasets
https://api.domo.com/v1/users
https://api.domo.com/v1/pages
https://api.domo.com/v1/streams
https://api.domo.com/v1/groups
```

**Product API endpoints** (Developer Token):
```
https://{instance}.domo.com/api/content/v1/cards
https://{instance}.domo.com/api/data/v1/datasets
https://{instance}.domo.com/api/identity/v1/users
https://{instance}.domo.com/api/workflow/v1/instances
https://{instance}.domo.com/api/codeengine/v1/functions
```

### Step 6: CORS Restrictions
- **Product APIs are CORS-restricted** — call server-side only.
- "Try It" in docs won't work from browser.
- Use Code Engine, Jupyter, or external backend for Product API calls.
- App Framework APIs work from browser (proxied through Domo).

### Step 7: Token Lifecycle Management
- **OAuth tokens**: Expire (default 1 hour). Re-generate with client credentials.
- **Product tokens**: Long-lived but revocable by admins.
- **Best practice**: Rotate tokens regularly, use shortest-lived token possible.
- Admins can revoke OAuth clients or Product tokens at any time.

### Step 8: SDK Usage

**Python SDK (pydomo):**
```python
from pydomo import Domo
domo = Domo(client_id, client_secret, api_host='api.domo.com')
datasets = domo.datasets.list()
```

**Java SDK (domo-java-sdk):**
```java
DomoClient client = DomoClient.create(clientId, clientSecret);
List<Dataset> datasets = client.datasetClient().list();
```

## Key References

- Three tiers: App Framework, Platform (OAuth), Product
- OAuth endpoint: `POST https://api.domo.com/oauth/token`
- Product header: `X-DOMO-Developer-Token`
- Scopes: data, user, dashboard, account, audit
- Platform base: `https://api.domo.com/v1/`
- Product base: `https://{instance}.domo.com/api/`
- SDKs: `pydomo` (Python), `domo-java-sdk` (Java)
- CORS: Product APIs are server-side only
- Token expiry: OAuth ~1hr, Product long-lived

## Examples

```bash
# Create a scoped OAuth client for data operations
/domo/api-integrate client-create --scopes "data" --name "Daily Sync"

# Authenticate and list datasets
/domo/api-integrate call --tier platform --endpoint "/v1/datasets" --limit 50

# Use Product API for workflow management
/domo/api-integrate call --tier product --endpoint "/api/workflow/v1/instances" --method GET
```
