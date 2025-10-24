# Snowflake Google Sheets Integration

Bi-directional data integration between Snowflake and Google Sheets using Python UDFs and Google Service Accounts.

## Table of Contents
- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Setup](#detailed-setup)
- [Usage Examples](#usage-examples)
- [Security Best Practices](#security-best-practices)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Additional Resources](#additional-resources)

---

## Overview

This project enables you to:
- **Read** data from Google Sheets into Snowflake tables
- **Write** Snowflake query results directly to Google Sheets
- Automate data exports using Snowflake tasks or dbt post-hooks
- Share analysis results with non-technical stakeholders

### Use Cases
- 📊 Export dashboards/reports to Google Sheets for distribution
- 📥 Import small reference data (pricing, mappings, configs) from Sheets
- 🔄 Sync data between Snowflake and spreadsheet-based workflows
- 📈 Build self-service analytics for business users
- 🤝 Collaborate with teams who work primarily in spreadsheets

### Architecture

```
Snowflake ←→ External Access Integration ←→ Google APIs ←→ Google Sheets
```

For detailed architecture information, see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Features

| Feature | Description |
|---------|-------------|
| **Read Function** | `read_gsheet(spreadsheet_id, sheet_id)` - Returns Google Sheet as JSON rows |
| **Write Procedure** | `write_to_gsheet(query, spreadsheet_id, sheet_id)` - Exports query results to Sheet |
| **Type Flexibility** | Returns VARIANT (JSON) for easy parsing in Snowflake |
| **Error Handling** | Returns structured error information when operations fail |
| **Secure** | Uses Snowflake secrets and external access controls |
| **No External Tools** | Everything runs natively in Snowflake |

---

## Prerequisites

### Required Access

#### Snowflake Permissions
| Task | Required Role | Alternative |
|------|--------------|-------------|
| Create Network Rules | ACCOUNTADMIN | Custom role with CREATE NETWORK RULE |
| Create Secrets | ACCOUNTADMIN or SECURITYADMIN | Custom role with CREATE SECRET |
| Create Integration | ACCOUNTADMIN | None (only ACCOUNTADMIN) |
| Create Functions | Database/Schema owner | USAGE + CREATE FUNCTION privilege |
| Execute Functions | Function owner | USAGE + EXECUTE privilege |

#### Google Cloud Platform
- Access to Google Cloud Console
- Permission to create Service Accounts
- Permission to download Service Account keys

#### Google Sheets
- Owner/Editor access to sheets you want to integrate
- Ability to share sheets with service account email

---

## Quick Start

### For Advanced Users

If you're familiar with Snowflake and GCP, here's the fast track:

```bash
# 1. Download your GCP service account JSON
# 2. Escape the JSON
python3 json_escape.py service_account.json

# 3. Run init.sql to create infrastructure
# 4. Create the secret with your escaped JSON
# 5. Deploy functions from read_gsheet.sql and write_gsheet.sql
# 6. Test with get_gcp_email() and share the sheet with that email
# 7. Start using read_gsheet() and write_to_gsheet()
```

See [examples.sql](examples.sql) for usage patterns.

---

## Detailed Setup

### Step 1: Create a Google Service Account

> 💡 **For Beginners:** A service account is like a "robot user" that your Snowflake functions will use to access Google Sheets.

#### 1.1 Navigate to Google Cloud Console
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project (or create a new one)
3. Navigate to **IAM & Admin** → **Service Accounts**

#### 1.2 Create Service Account
1. Click **Create Service Account**
2. Enter a name (e.g., `snowflake-sheets-integration`)
3. Add description: "Service account for Snowflake Google Sheets integration"
4. Click **Create and Continue**

#### 1.3 Set Permissions (Optional)
- For basic Google Sheets access, no additional roles are needed
- For Google Drive API access, add "Drive API" permissions
- Click **Continue**, then **Done**

#### 1.4 Generate Key File
1. Find your service account in the list
2. Click on it to open details
3. Go to the **Keys** tab
4. Click **Add Key** → **Create new key**
5. Select **JSON** format
6. Click **Create** - a JSON file will download

#### 1.5 Review Key File
Your downloaded file should look like:
```json
{
  "type": "service_account",
  "project_id": "your-project-123",
  "private_key_id": "abc123...",
  "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvQ...\n-----END PRIVATE KEY-----\n",
  "client_email": "snowflake-sheets@your-project.iam.gserviceaccount.com",
  "client_id": "123456789",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/..."
}
```

---

### Step 2: Prepare Credentials for Snowflake

> 💡 **For Beginners:** Snowflake needs this JSON in a special format - as a single line with escaped characters.

#### 2.1 Escape the JSON

**Option A: Using the provided Python script (Recommended)**
```bash
python3 json_escape.py service_account.json
```

**Option B: Using command-line tools**
```bash
cat service_account.json | jq -c . | sed 's/\\n/\\\\n/g'
```

Copy the output - you'll need it in the next step.

---

### Step 3: Set Up Snowflake Infrastructure

#### 3.1 Create Network Rules

> 💡 **For Beginners:** Network rules tell Snowflake which external websites your functions can access.

```sql
-- Allow access to Google OAuth for authentication
CREATE OR REPLACE NETWORK RULE google_oauth
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = ('oauth2.googleapis.com');

-- Allow access to Google Sheets API
CREATE OR REPLACE NETWORK RULE google_sheets
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = ('sheets.googleapis.com');
```

#### 3.2 Create Secret

> ⚠️ **Important:** Requires ACCOUNTADMIN or SECURITYADMIN role.

```sql
CREATE OR REPLACE SECRET GSHEET_CREDENTIALS
  TYPE = GENERIC_STRING
  SECRET_STRING = '<PASTE_YOUR_ESCAPED_JSON_HERE>';
```

Replace `<PASTE_YOUR_ESCAPED_JSON_HERE>` with the output from Step 2.1.

#### 3.3 Create External Access Integration

> ⚠️ **Important:** Requires ACCOUNTADMIN role.

```sql
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION csv_download_integration
  ALLOWED_NETWORK_RULES = (google_oauth, google_sheets)
  ALLOWED_AUTHENTICATION_SECRETS = (GSHEET_CREDENTIALS)
  ENABLED = TRUE;
```

> 💡 **For Advanced Users:** You can customize the integration name, but remember to update all function definitions accordingly.

---

### Step 4: Deploy Functions

#### 4.1 Test Function (Optional but Recommended)

Deploy the test function to verify your credentials:

```sql
-- Paste contents of test_creds.sql here
```

Then test it:
```sql
SELECT get_gcp_email();
-- Should return: service-account-name@project-id.iam.gserviceaccount.com
```

**If this fails:** Your credentials aren't properly configured. See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

#### 4.2 Deploy Read Function

```sql
-- Paste contents of read_gsheet.sql
```

#### 4.3 Deploy Write Procedure

```sql
-- Paste contents of write_gsheet.sql
```

---

### Step 5: Share Google Sheet with Service Account

> 💡 **For Beginners:** Your service account needs explicit permission to access each Google Sheet.

#### 5.1 Get Service Account Email
```sql
SELECT get_gcp_email();
```

#### 5.2 Share the Sheet
1. Open your Google Sheet
2. Click **Share** button (top-right)
3. Paste the service account email
4. Grant **Viewer** permission (for read-only) or **Editor** (for read/write)
5. **UNCHECK** "Notify people" (service accounts can't receive emails)
6. Click **Send**

---

### Step 6: Test the Integration

#### 6.1 Test Reading

```sql
-- Replace with your spreadsheet ID and sheet ID
SELECT * 
FROM TABLE(read_gsheet('your_spreadsheet_id', 0))
LIMIT 10;
```

**How to find IDs:**
From URL: `https://docs.google.com/spreadsheets/d/SPREADSHEET_ID/edit#gid=SHEET_ID`
- `SPREADSHEET_ID`: The long string in the URL
- `SHEET_ID`: Number after `gid=` (first tab is usually `0`)

#### 6.2 Test Writing

```sql
-- Create a simple test
CALL write_to_gsheet(
    'SELECT 1 as id, ''test'' as name',
    'your_spreadsheet_id',
    0
);
```

Check your Google Sheet - it should now contain the data!

---

## Usage Examples

### Reading Data from Google Sheets

#### Basic Read
```sql
-- Get all data as JSON
SELECT * 
FROM TABLE(read_gsheet('1abc123XYZ', 0));
```

#### Parse JSON Columns
```sql
-- Extract specific columns with types
SELECT 
    row_data:"id"::INT as id,
    row_data:"name"::STRING as name,
    row_data:"email"::STRING as email,
    row_data:"created_date"::DATE as created_date
FROM TABLE(read_gsheet('1abc123XYZ', 0));
```

#### Create Table from Sheet
```sql
CREATE OR REPLACE TABLE my_reference_data AS
SELECT 
    row_data:"product_id"::INT as product_id,
    row_data:"product_name"::STRING as product_name,
    row_data:"price"::FLOAT as price
FROM TABLE(read_gsheet('1abc123XYZ', 0));
```

#### Join with Existing Tables
```sql
SELECT 
    o.order_id,
    o.product_id,
    g.row_data:"discount"::FLOAT as current_discount
FROM orders o
JOIN TABLE(read_gsheet('1abc123XYZ', 0)) g
    ON o.product_id = g.row_data:"product_id"::INT;
```

### Writing Data to Google Sheets

#### Basic Write
```sql
CALL write_to_gsheet(
    'SELECT user_id, name, email FROM users LIMIT 100',
    '1abc123XYZ',
    0
);
```

#### Export Aggregated Data
```sql
CALL write_to_gsheet(
    'SELECT 
        DATE_TRUNC(''month'', order_date) as month,
        COUNT(*) as order_count,
        SUM(amount) as total_revenue
     FROM orders
     WHERE order_date >= DATEADD(month, -12, CURRENT_DATE())
     GROUP BY 1
     ORDER BY 1',
    '1abc123XYZ',
    0
);
```

#### Export to Different Tabs
```sql
-- Export to first tab (Sheet ID = 0)
CALL write_to_gsheet('SELECT * FROM sales_summary', '1abc123XYZ', 0);

-- Export to second tab (find Sheet ID in URL)
CALL write_to_gsheet('SELECT * FROM inventory_status', '1abc123XYZ', 123456);
```

### Advanced Usage

#### Scheduled Exports with Tasks
```sql
CREATE OR REPLACE TASK daily_report_export
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = 'USING CRON 0 9 * * * UTC'  -- Daily at 9 AM UTC
AS
  CALL write_to_gsheet(
    'SELECT * FROM daily_metrics WHERE report_date = CURRENT_DATE()',
    '1abc123XYZ',
    0
  );

-- Enable the task
ALTER TASK daily_report_export RESUME;
```

#### Integration with dbt
Add to your dbt model's config:

```yaml
{{ config(
    post_hook=[
        "CALL write_to_gsheet('SELECT * FROM {{ this }}', '1abc123XYZ', 0)"
    ]
) }}
```

#### Error Handling
```sql
-- Check if operation succeeded
CALL write_to_gsheet('SELECT * FROM my_table', '1abc123XYZ', 0);

-- The procedure returns a status variant
-- On success: {"status": "success"}
-- On error: {"error": "message", "error_type": "type", ...}
```

For more examples, see [examples.sql](examples.sql).

---

## Security Best Practices

### 1. Secret Management
- ✅ Use separate service accounts for dev/staging/prod
- ✅ Rotate service account keys regularly (every 90 days recommended)
- ✅ Delete old/unused service accounts
- ✅ Monitor secret access using Snowflake query history
- ❌ Never share service account JSON files via email or Slack
- ❌ Never commit service account JSON to git

### 2. Access Control

#### Snowflake Side
```sql
-- Limit who can execute functions
GRANT USAGE ON FUNCTION read_gsheet(STRING, NUMBER) TO ROLE analyst_role;
GRANT USAGE ON PROCEDURE write_to_gsheet(STRING, STRING, NUMBER) TO ROLE etl_role;

-- Don't grant access to the integration itself to regular users
-- Only admins need access to integrations
```

#### Google Side
- Only share sheets with the service account that need integration
- Use "Viewer" permission for read-only use cases
- Regularly audit which sheets are shared with service accounts
- Consider using Google Drive folders with service account access

### 3. Network Security
- Network rules are restrictive by design (only allows specified hosts)
- Don't add wildcard rules
- Monitor Snowflake query history for unusual external access patterns

### 4. Data Privacy
- Don't export sensitive data (PII, PCI, PHI) to Google Sheets without proper controls
- Google Sheets is not a secure data warehouse
- Consider data masking/anonymization before export
- Check your organization's data governance policies

---

## Troubleshooting

For detailed troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

### Quick Checks

**Functions not working?**
1. ✓ Run `SELECT get_gcp_email()` - if this fails, credentials are wrong
2. ✓ Check if sheet is shared with the service account email
3. ✓ Verify spreadsheet ID and sheet ID are correct
4. ✓ Ensure network rules and integration exist

**Permission errors?**
- Snowflake: Check you have USAGE on integration and functions
- Google: Make sure service account is shared on the specific sheet

**JSON parsing errors?**
- Ensure your secret was created with properly escaped JSON
- Private key newlines must be `\\n` (double backslash)

---

## FAQ

### Q: Do I need to create a new service account for each Snowflake environment?
**A:** It's recommended. Use separate service accounts for dev, staging, and production for better security and auditability.

### Q: Can I read/write multiple sheets at once?
**A:** Not directly. You need to call the function/procedure once per sheet. Consider creating a stored procedure that loops through multiple sheets if needed.

### Q: What's the performance impact?
**A:** Each call makes external API requests (2-5 seconds typical). For frequently accessed data, cache results in a Snowflake table.

### Q: Are there data size limits?
**A:** Google Sheets supports up to 10 million cells. For larger datasets, consider alternative export methods.

### Q: Can I use this with Excel files?
**A:** No, this integration is specifically for Google Sheets. For Excel, consider exporting to CSV and using Snowflake stages.

### Q: Does this count against Snowflake credits?
**A:** Yes, UDF and stored procedure execution consumes compute credits based on your warehouse size.

### Q: Can I schedule automatic exports?
**A:** Yes! Use Snowflake tasks or integrate with your orchestration tool (Airflow, dbt, etc.).

### Q: What happens if Google Sheets API is down?
**A:** Functions will fail with network errors. Implement retry logic in your orchestration if reliability is critical.

### Q: Can multiple Snowflake functions access the same sheet simultaneously?
**A:** Yes, but be careful with writes - they overwrite starting from A1. Consider using different tabs or separate sheets.

---

## Additional Resources

- [ARCHITECTURE.md](ARCHITECTURE.md) - Detailed technical architecture
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Comprehensive troubleshooting guide
- [examples.sql](examples.sql) - More usage examples
- [Snowflake External Access Integration Docs](https://docs.snowflake.com/en/sql-reference/sql/create-external-access-integration)
- [Google Sheets API Documentation](https://developers.google.com/sheets/api)
- [gspread Library Documentation](https://docs.gspread.org/)

---

## Contributing

Found an issue or have an improvement? Contributions are welcome!

## License

This project is provided as-is for use within your organization.
