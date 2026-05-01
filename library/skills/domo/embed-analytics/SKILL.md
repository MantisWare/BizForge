---
name: domo/embed-analytics
description: >
  Embed Domo content (cards, dashboards, apps) into external sites and software.
  Covers authentication methods, programmatic filters, iframe configuration,
  Safari cookie mitigation, and multi-language backend examples.
  Triggers on: "embed", "embedded analytics", "iframe domo", "embed token", "private embed"
---

# /domo/embed-analytics

> Embed Domo cards, dashboards, and apps into external websites and applications.

## Purpose

Domo's embedded analytics allows you to surface Domo content (cards, dashboards, custom apps) inside external websites, portals, and applications. This skill covers authentication patterns (embed tokens, header-based auth), programmatic filtering, iframe sizing, Safari/third-party cookie mitigation, and provides backend examples in multiple languages.

## Usage

```bash
# Generate embed configuration for a card
/domo/embed-analytics configure --card-id 12345 --auth private --filters "region=West"

# Set up header-based auth for Safari compatibility
/domo/embed-analytics safari-fix --app-id APP123

# Generate backend token endpoint
/domo/embed-analytics backend --lang python --card-id 12345
```

## Process

### Step 1: Choose Embed Type

| Type | Auth | Audience | Use Case |
|------|------|----------|----------|
| Private Embed | Embed Token | Authenticated users | Internal portals, apps |
| Public Embed | None | Anyone with URL | Public dashboards |
| App Embed | App Session | Domo users | Custom apps in iframes |

### Step 2: Private Embed Authentication

**Generate Embed Token (OAuth API):**
```
POST /v1/tokens/embed
Headers: Authorization: Bearer {access_token}
Body: {
  "tokenType": "PRIVATE",
  "resources": [{ "type": "CARD", "id": "12345" }],
  "policies": [
    { "type": "FILTER", "column": "region", "values": ["West"] }
  ]
}
```

The token is then passed to the embed iframe URL to authenticate the viewer.

### Step 3: Header-Based Auth (Safari Fix)

Safari blocks third-party cookies, breaking cookie-based embed auth. Use header-based authentication instead:

**Frontend (load token into global):**
```javascript
window.__RYUU_AUTHENTICATION_TOKEN__ = 'your-embed-token';
```

**Or pass via header:**
```
X-DOMO-Ryuu-Token: {embed_token}
```

This bypasses third-party cookie restrictions entirely.

### Step 4: Programmatic Filters

Apply filters to embedded content via URL parameters:
```
https://{instance}.domo.com/embed/card/{cardId}?pfilters=[
  {"column": "region", "operator": "IN", "values": ["West", "East"]},
  {"column": "year", "operator": "EQUALS", "values": ["2024"]}
]
```

**Filter operators:** `IN`, `NOT_IN`, `EQUALS`, `NOT_EQUALS`, `GREATER_THAN`, `LESS_THAN`, `BETWEEN`

Note: Only use URL params for non-sensitive filtering. For security-sensitive filters, use embed token policies.

### Step 5: Iframe Configuration

```html
<iframe
  src="https://{instance}.domo.com/embed/card/{cardId}"
  width="100%"
  height="600"
  frameborder="0"
  allowfullscreen
></iframe>
```

Dynamic height adjustment:
```javascript
window.addEventListener('message', (event) => {
  if (event.data.type === 'domo-embed-resize') {
    document.getElementById('domo-iframe').height = event.data.height;
  }
});
```

### Step 6: Backend Token Generation Examples

**Python:**
```python
import requests

def get_embed_token(card_id, filters=None):
    token_url = f"https://{INSTANCE}.domo.com/v1/tokens/embed"
    headers = {"Authorization": f"Bearer {ACCESS_TOKEN}"}
    body = {
        "tokenType": "PRIVATE",
        "resources": [{"type": "CARD", "id": card_id}],
        "policies": filters or []
    }
    response = requests.post(token_url, json=body, headers=headers)
    return response.json()["token"]
```

**Node.js:**
```javascript
async function getEmbedToken(cardId, filters = []) {
  const response = await fetch(`https://${INSTANCE}.domo.com/v1/tokens/embed`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${ACCESS_TOKEN}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      tokenType: 'PRIVATE',
      resources: [{ type: 'CARD', id: cardId }],
      policies: filters
    })
  });
  const data = await response.json();
  return data.token;
}
```

### Step 7: IDP Whitelisting (SSO Environments)
For embedded apps in SSO-protected environments, whitelist:
- `*.domoapps.*.domo.com`

Supported IDPs: Okta, Azure AD, Ping, SailPoint, OneLogin, ForgeRock, Centrify.

### Step 8: Salesforce Lightning Embedding
Embed Domo content in Salesforce:
1. Create a Lightning Web Component or Visualforce page.
2. Use the Domo embed URL with token authentication.
3. Pass Salesforce context (user, account) as filter parameters.
4. Reference: `domoinc/domo-salesforce-embed` repo.

## Key References

- Embed Token API: `POST /v1/tokens/embed`
- Safari fix: `window.__RYUU_AUTHENTICATION_TOKEN__` or `X-DOMO-Ryuu-Token` header
- Programmatic filters: `pfilters` URL parameter (JSON array)
- Filter operators: IN, NOT_IN, EQUALS, NOT_EQUALS, GREATER_THAN, LESS_THAN, BETWEEN
- IDP whitelist: `*.domoapps.*.domo.com`
- Backend samples: Python, Node.js, .NET, PHP
- Salesforce: Lightning Web Component integration
- Iframe resize: `domo-embed-resize` message event

## Examples

```bash
# Configure private embed with region filter
/domo/embed-analytics configure --card-id 12345 --filter "region:West" --auth private

# Generate Python backend for token management
/domo/embed-analytics backend --lang python --instance mycompany

# Fix Safari auth issues for embedded app
/domo/embed-analytics safari-fix --use-header-auth
```
