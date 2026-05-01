---
name: domo/governance
description: >
  Manage Domo governance including user/group management, SSO configuration,
  activity log monitoring, content management, PDP policies, security controls,
  certified content, and role-based access governance.
  Triggers on: "governance", "user management", "sso", "activity log", "pdp", "security policy", "certified content"
---

# /domo/governance

> Manage Domo platform governance: users, groups, SSO, security, content, and audit trails.

## Purpose

Domo governance ensures proper access control, security compliance, and content quality across the platform. This skill covers user and group management, SSO configuration, activity log monitoring, content management and certification, PDP (Personalized Data Permissions), security scanning, and role-based governance policies.

## Usage

```bash
# Manage users
/domo/governance users --action list --role admin

# Configure SSO
/domo/governance sso --provider okta --protocol saml

# Query activity logs
/domo/governance audit --action "DATASET_EXPORT" --days 30

# Certify content
/domo/governance certify --card-id 12345 --status certified
```

## Process

### Step 1: User Management

**List Users:**
```
GET /v1/users?limit=50&offset=0
Headers: Authorization: Bearer {access_token}
```

**Create User:**
```
POST /v1/users
Body: {
  "name": "Jane Smith",
  "email": "jane@company.com",
  "role": "Participant"
}
```

**Roles:** Admin, Privileged, Editor, Participant, Social

**Update User:**
```
PUT /v1/users/{userId}
Body: { "role": "Editor", "title": "Data Analyst" }
```

**Delete User:**
```
DELETE /v1/users/{userId}
```

### Step 2: Group Management

**Create Group:**
```
POST /v1/groups
Body: { "name": "Analytics Team", "type": "open" }
```

**Add Users to Group:**
```
PUT /v1/groups/{groupId}/users/{userId}
```

**List Group Members:**
```
GET /v1/groups/{groupId}/users
```

Groups are used for PDP policies, content sharing, and permission management.

### Step 3: SSO Configuration

**Supported Protocols:**
- SAML 2.0 (Okta, Azure AD, Ping, OneLogin)
- OAuth 2.0 (Azure AD, custom providers)

**Configuration Steps:**
1. Enable SSO in Admin > Security > SSO.
2. Configure IdP metadata (entity ID, SSO URL, certificate).
3. Map IdP attributes to Domo user fields.
4. Test with a pilot group before full rollout.
5. Configure auto-provisioning (JIT) if desired.

**IDP Whitelisting for Embedded Apps:**
Whitelist `*.domoapps.*.domo.com` in your IdP for embedded scenarios.

### Step 4: Activity Log Monitoring

**Query Activity Logs:**
```
GET /v1/audit?start=1699977600000&end=1700064000000&limit=100
Headers: Authorization: Bearer {access_token}
```

**Key Event Types:**
- `DATASET_EXPORT` — Data was exported
- `LOGIN` — User authentication
- `CARD_VIEW` — Content accessed
- `PERMISSION_CHANGE` — Access modified
- `USER_CREATED` / `USER_DELETED`
- `PDP_POLICY_CREATED` / `PDP_POLICY_UPDATED`

**Use Cases:**
- Security auditing and compliance reporting.
- Track data access patterns.
- Detect unusual activity (bulk exports, off-hours access).
- Compliance documentation (SOX, HIPAA, GDPR).

### Step 5: Content Management

**Certified Content:**
Mark trusted, validated content as "certified":
- Cards, dashboards, and datasets can be certified.
- Certified content appears with a badge in the UI.
- Helps users distinguish authoritative from experimental content.

**Content Organization:**
- Pages (dashboards) organized hierarchically.
- Collections for cross-page content grouping.
- Tags for discoverability.
- Ownership tracking and transfer.

### Step 6: PDP (Personalized Data Permissions)

Row-level security applied at the dataset level:
```
POST /v1/datasets/{datasetId}/policies
Body: {
  "name": "Sales Team West",
  "type": "user",
  "users": [12345, 67890],
  "filters": [
    { "column": "region", "values": ["West"] }
  ]
}
```

**Policy Types:**
- **User policy**: Specific users see specific rows.
- **Group policy**: Group members see filtered data.
- **System policy**: Default for all non-admin users.

**Best Practices:**
- Apply PDP at the source dataset, not derived datasets.
- Test policies with "View As" feature.
- Document policy logic for audit purposes.
- Use groups over individual users for maintainability.

### Step 7: Security Controls

- **IP whitelisting**: Restrict access by network.
- **Session management**: Configure timeout policies.
- **Password policies**: Complexity, rotation, MFA.
- **API token governance**: Regular rotation, admin revocation.
- **Data encryption**: At-rest and in-transit (platform-managed).

### Step 8: Role Governance

Define custom roles beyond the built-in set:
- Map business functions to platform permissions.
- Limit admin access to essential personnel.
- Use Privileged role for power users (Beast Mode, ETL).
- Audit role assignments quarterly.

## Key References

- User API: `/v1/users`
- Group API: `/v1/groups`
- Activity Log API: `/v1/audit`
- PDP API: `/v1/datasets/{id}/policies`
- Roles: Admin, Privileged, Editor, Participant, Social
- SSO: SAML 2.0, OAuth 2.0
- Certified content: Badge-based trust marking
- Security: IP whitelist, session timeout, MFA

## Examples

```bash
# Bulk create users from CSV
/domo/governance users --action bulk-create --file users.csv

# Set up SAML SSO with Okta
/domo/governance sso --provider okta --entity-id "https://company.okta.com"

# Create PDP policy for regional access
/domo/governance pdp --dataset "Sales" --group "West Team" --filter "region=West"

# Export 30-day audit trail
/domo/governance audit --days 30 --export csv
```
