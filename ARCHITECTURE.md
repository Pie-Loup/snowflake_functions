# Architecture Overview

## System Components

This project enables bi-directional data flow between Snowflake and Google Sheets using Snowflake's External Access Integration feature and Google Cloud Platform (GCP) Service Accounts.

```
┌─────────────────────────────────────────────────────────────────┐
│                        Snowflake Account                         │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  Python UDF/UDTF (read_gsheet)                         │    │
│  │  Python Stored Procedure (write_to_gsheet)             │    │
│  └──────────────────┬─────────────────────────────────────┘    │
│                     │                                            │
│  ┌──────────────────▼─────────────────────────────────────┐    │
│  │  External Access Integration                            │    │
│  │  - Manages outbound network access                      │    │
│  │  - Controls authentication secrets                      │    │
│  └──────────────────┬─────────────────────────────────────┘    │
│                     │                                            │
│  ┌──────────────────▼─────────────────────────────────────┐    │
│  │  Network Rules                                          │    │
│  │  - oauth2.googleapis.com  (authentication)              │    │
│  │  - sheets.googleapis.com  (API access)                  │    │
│  └──────────────────┬─────────────────────────────────────┘    │
│                     │                                            │
│  ┌──────────────────▼─────────────────────────────────────┐    │
│  │  Snowflake Secret (GSHEET_CREDENTIALS)                  │    │
│  │  - Stores GCP Service Account JSON                      │    │
│  │  - Encrypted at rest                                    │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
└──────────────────────────┬───────────────────────────────────────┘
                           │ HTTPS
                           │
┌──────────────────────────▼───────────────────────────────────────┐
│                    Google Cloud Platform                         │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  OAuth 2.0 Service (oauth2.googleapis.com)              │   │
│  │  - Authenticates service account                         │   │
│  │  - Issues access tokens                                  │   │
│  └──────────────────┬──────────────────────────────────────┘   │
│                     │                                            │
│  ┌──────────────────▼──────────────────────────────────────┐   │
│  │  Google Sheets API (sheets.googleapis.com)              │   │
│  │  - Read operations (get_all_records)                     │   │
│  │  - Write operations (update)                             │   │
│  └──────────────────┬──────────────────────────────────────┘   │
│                     │                                            │
│  ┌──────────────────▼──────────────────────────────────────┐   │
│  │  Google Sheet Document                                   │   │
│  │  - Shared with service account email                     │   │
│  │  - Read/Write permissions granted                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. Snowflake External Access Integration

The External Access Integration is Snowflake's security mechanism for allowing Python UDFs and stored procedures to make outbound HTTP requests.

**Key features:**
- Controls which external endpoints can be accessed (via Network Rules)
- Manages authentication credentials (via Secrets)
- Provides audit trail of external connections
- Requires ACCOUNTADMIN or appropriate privileges to create

**Why it's needed:**
Without this, Python functions in Snowflake cannot make any network calls to external services.

### 2. Network Rules

Network Rules define the specific hosts and ports that Snowflake functions can access.

**Our configuration:**
- `google_oauth`: Allows access to `oauth2.googleapis.com` for authentication
- `google_sheets`: Allows access to `sheets.googleapis.com` for API operations

**Security model:**
- Egress-only (outbound from Snowflake)
- Host:Port based filtering
- No wildcards - must explicitly list each domain

### 3. Snowflake Secrets

Secrets are encrypted storage for sensitive data like API keys, credentials, and tokens.

**Our secret (`GSHEET_CREDENTIALS`):**
- Type: `GENERIC_STRING`
- Content: Complete GCP Service Account JSON
- Encryption: Automatic at rest using Snowflake's encryption
- Access: Only accessible from functions that explicitly declare them

**Important:** The JSON must be properly escaped (newlines as `\\n`) and compacted to a single line.

### 4. GCP Service Account

A service account is a special type of Google account that belongs to an application rather than a person.

**Key components:**
- **Email:** `service-account-name@project-id.iam.gserviceaccount.com`
- **Private Key:** Used for authentication (RSA key pair)
- **Scopes:** Defines what APIs the account can access

**Authentication flow:**
1. Function loads service account JSON from Snowflake secret
2. Creates JWT (JSON Web Token) signed with private key
3. Exchanges JWT for OAuth 2.0 access token at `oauth2.googleapis.com`
4. Uses access token to make API calls to `sheets.googleapis.com`

### 5. Python Functions

#### read_gsheet (Table Function)
- **Type:** User-Defined Table Function (UDTF)
- **Returns:** One row per Google Sheet row as VARIANT (JSON)
- **Execution:** On-demand, when queried
- **Libraries:** `gspread`, `google-auth`

**Process:**
1. Retrieve secret from Snowflake
2. Authenticate with GCP
3. Fetch all records from specified sheet
4. Yield each row as JSON variant

#### write_to_gsheet (Stored Procedure)
- **Type:** Stored Procedure
- **Input:** SQL query string, spreadsheet ID, sheet ID
- **Returns:** Status variant (success/error)
- **Libraries:** `snowflake-snowpark-python`, `gspread`, `google-auth`

**Process:**
1. Execute SQL query using Snowpark
2. Collect results into list of lists
3. Retrieve secret and authenticate
4. Write data to Google Sheet starting at A1
5. Return success or error information

## Data Flow

### Read Flow (Snowflake ← Google Sheets)

```
User Query
    │
    ▼
SELECT * FROM TABLE(read_gsheet('sheet_id', 0))
    │
    ▼
Python UDTF Execution
    │
    ├─→ Load secret from Snowflake
    ├─→ Authenticate with GCP OAuth
    ├─→ Call Google Sheets API
    ├─→ Fetch all records
    │
    ▼
Return VARIANT rows
    │
    ▼
User can parse JSON:
SELECT row_data:"column_name"::type
```

### Write Flow (Snowflake → Google Sheets)

```
User Call
    │
    ▼
CALL write_to_gsheet('SELECT ...', 'sheet_id', 0)
    │
    ▼
Stored Procedure Execution
    │
    ├─→ Execute SQL query via Snowpark
    ├─→ Collect results + column names
    ├─→ Load secret from Snowflake
    ├─→ Authenticate with GCP OAuth
    ├─→ Call Google Sheets API
    ├─→ Update sheet with data
    │
    ▼
Return success/error status
```

## Security Considerations

### 1. Secret Management
- Secrets never leave Snowflake in plain text
- Only accessible from declared functions
- Audit logs track secret access
- Regular rotation recommended

### 2. Network Isolation
- Functions can only access explicitly allowed domains
- No wildcard access
- All traffic encrypted (HTTPS)

### 3. Service Account Permissions
- Use principle of least privilege
- Only grant necessary scopes
- Don't share service account across projects unnecessarily
- Monitor usage through GCP logs

### 4. Google Sheet Access
- Service account must be explicitly shared on each sheet
- Can grant read-only or edit permissions
- Doesn't count against user quotas

## Performance Considerations

### Read Operations
- **Latency:** ~2-5 seconds for small sheets (<1000 rows)
- **Bottleneck:** Network calls to Google API
- **Optimization:** Cache results in Snowflake table if accessed frequently
- **Limitations:** Google Sheets API has quotas (100 requests/100 seconds/user)

### Write Operations
- **Latency:** ~3-10 seconds depending on data size
- **Bottleneck:** Snowpark query execution + API write
- **Optimization:** Batch writes when possible
- **Limitations:** Google Sheets limited to 10 million cells per sheet

## Extension Points

### Adding New Google APIs
To integrate other Google services:
1. Add appropriate network rule (e.g., `drive.googleapis.com`)
2. Update service account scopes
3. Add Python package to function definition
4. Create new UDF/procedure with similar pattern

### Error Handling
Functions return error information as VARIANT when operations fail:
```json
{
  "error": "Error message",
  "error_type": "ExceptionName",
  "url": "sheet_id or additional context"
}
```

### Integration with dbt
Use post-hooks to export tables:
```yaml
post-hook:
  - "CALL write_to_gsheet('SELECT * FROM {{ this }}', 'sheet_id', 0)"
```

