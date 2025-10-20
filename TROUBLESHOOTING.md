# Troubleshooting Guide

This guide covers common issues you may encounter when setting up or using the Snowflake Google Sheets integration.

## Table of Contents
- [Setup Issues](#setup-issues)
- [Authentication Errors](#authentication-errors)
- [Permission Errors](#permission-errors)
- [Network Issues](#network-issues)
- [Function Execution Errors](#function-execution-errors)
- [Google Sheets API Errors](#google-sheets-api-errors)
- [Debug Checklist](#debug-checklist)

---

## Setup Issues

### Error: "Insufficient privileges to operate on SECRET"

**Symptom:** Cannot create secret in Snowflake

**Cause:** You don't have the required role privileges

**Solution:**
```sql
-- Ask your admin to grant you the required role
USE ROLE ACCOUNTADMIN;  -- or SECURITYADMIN

-- Or have them grant you secret creation privileges
GRANT CREATE SECRET ON SCHEMA <schema_name> TO ROLE <your_role>;
```

**Who can create secrets:**
- ACCOUNTADMIN
- SECURITYADMIN
- Role with explicit CREATE SECRET privilege

---

### Error: "Insufficient privileges to operate on EXTERNAL ACCESS INTEGRATION"

**Symptom:** Cannot create external access integration

**Cause:** Only ACCOUNTADMIN can create integrations

**Solution:**
```sql
USE ROLE ACCOUNTADMIN;
-- Then run your CREATE EXTERNAL ACCESS INTEGRATION command
```

**Note:** This is a security feature. Only admins should control external access.

---

### Error: JSON escaping issues with private key

**Symptom:** Secret created but functions fail with "Invalid JWT" or "Private key error"

**Cause:** Newlines in the private key weren't properly escaped

**Solution:**
```bash
# Method 1: Use the provided script
python3 json_escape.py service_account.json

# Method 2: Use jq and sed
cat service_account.json | jq -c . | sed 's/\\n/\\\\n/g'

# Method 3: Manual fix - ensure \n becomes \\n in the private_key field
```

**Validation:**
Your secret string should have `\\\\n` (four backslashes) in the private key:
```json
{"private_key":"-----BEGIN PRIVATE KEY-----\\nMIIEvQ...\\n-----END PRIVATE KEY-----\\n"}
```

---

## Authentication Errors

### Error: "Invalid JWT: Token must be a short-lived token..."

**Symptom:** Functions fail when trying to authenticate with Google

**Cause:** 
1. Private key wasn't properly escaped
2. Service account JSON is malformed
3. Clock skew between Snowflake and Google servers

**Solution:**
```sql
-- Test your credentials with the simple function
SELECT get_gcp_email();

-- If this fails, recreate your secret with properly escaped JSON
CREATE OR REPLACE SECRET GSHEET_CREDENTIALS
  TYPE = GENERIC_STRING
  SECRET_STRING = '<properly_escaped_json>';
```

---

### Error: "Credentials could not be obtained from environment"

**Symptom:** Python function fails to authenticate

**Cause:** Secret name mismatch in function definition

**Solution:**
Check that your function's SECRETS parameter matches your secret name:
```sql
-- In your function definition:
SECRETS = ('credential' = GSHEET_CREDENTIALS)
         -- ↑ This is the alias used in Python code
                   -- ↑ This must match your actual secret name
```

---

## Permission Errors

### Error: "The caller does not have permission" from Google API

**Symptom:** Authentication succeeds but API calls fail

**Cause:** Service account not granted access to the Google Sheet

**Solution:**
```sql
-- 1. Get your service account email
SELECT get_gcp_email();

-- 2. In Google Sheets, click Share
-- 3. Add the service account email (looks like: xxx@yyy.iam.gserviceaccount.com)
-- 4. Grant "Viewer" (for read) or "Editor" (for write) permission
-- 5. Ensure "Notify people" is UNCHECKED (service accounts can't receive emails)
```

**Common mistake:** Forgetting to click "Send" after adding the email.

---

### Error: "Access Denied: External Access Integration not found"

**Symptom:** Function fails to execute with access denied

**Cause:** Function doesn't have permission to use the integration

**Solution:**
```sql
-- Grant usage on integration to your role
USE ROLE ACCOUNTADMIN;
GRANT USAGE ON INTEGRATION csv_download_integration TO ROLE <your_role>;

-- Grant execute on the function
GRANT USAGE ON FUNCTION read_gsheet(STRING, NUMBER) TO ROLE <user_role>;
```

---

## Network Issues

### Error: "Network error" or "Connection timeout"

**Symptom:** Functions hang or fail with network errors

**Cause:** 
1. Network rules not properly configured
2. Corporate firewall blocking Snowflake egress
3. Google APIs temporarily unavailable

**Solution:**
```sql
-- Verify network rules exist
SHOW NETWORK RULES;

-- Verify integration references correct rules
SHOW INTEGRATIONS LIKE 'csv_download_integration';

-- Check if rules are properly linked
DESC INTEGRATION csv_download_integration;
```

**For Snowflake Admins:**
- Ensure your Snowflake account allows external access
- Check if any network policies are blocking egress
- Verify firewall rules allow HTTPS to googleapis.com

---

### Error: "Host not allowed"

**Symptom:** Function fails with "Host X is not in allowed list"

**Cause:** Network rule doesn't include required host

**Solution:**
```sql
-- Check your current network rules
SHOW NETWORK RULES;

-- Ensure both rules exist and are correct:
-- 1. oauth2.googleapis.com (for authentication)
-- 2. sheets.googleapis.com (for API calls)

-- If missing, create them as shown in init.sql
```

---

## Function Execution Errors

### Error: "Sheet not found" or "Invalid sheet ID"

**Symptom:** Function returns error about missing sheet

**Cause:** 
1. Spreadsheet ID is incorrect
2. Sheet ID (tab ID) is wrong
3. Sheet was deleted

**Solution:**
```bash
# Extract correct IDs from URL:
# https://docs.google.com/spreadsheets/d/SPREADSHEET_ID/edit#gid=SHEET_ID
#                                        ^^^^^^^^^^^^^^            ^^^^^^^^
# Example URL:
# https://docs.google.com/spreadsheets/d/1abc123XYZ/edit#gid=456

# Spreadsheet ID: 1abc123XYZ
# Sheet ID: 456 (the first tab is usually 0)
```

**Verify access:**
```sql
-- Test with a known good spreadsheet
SELECT * FROM TABLE(read_gsheet('your_spreadsheet_id', 0));
```

---

### Error: Function returns JSON with "error" field

**Symptom:** Query succeeds but returns error information

**Example output:**
```json
{
  "error": "Worksheet not found",
  "error_type": "WorksheetNotFound",
  "url": "your_spreadsheet_id"
}
```

**Solution:**
The function caught an exception and returned it as structured data.

**Common causes:**
- Sheet ID doesn't exist (check tab IDs in Google Sheets)
- Sheet was deleted
- Permission issues (service account removed from sheet)

**Debug:**
```sql
-- Check what error you're getting
SELECT 
    row_data:"error"::string as error_message,
    row_data:"error_type"::string as error_type
FROM TABLE(read_gsheet('your_id', 0))
WHERE row_data:"error" IS NOT NULL;
```

---

### Error: "Cannot import package X"

**Symptom:** Function fails with import error

**Cause:** Package name typo or package not in Snowflake's repository

**Solution:**
```sql
-- For read_gsheet, ensure packages are:
PACKAGES = ('gspread', 'google-auth')

-- For write_to_gsheet, ensure packages are:
PACKAGES = ('snowflake-snowpark-python', 'gspread', 'google-auth')

-- Check available packages:
-- https://repo.anaconda.com/pkgs/snowflake/
```

---

## Google Sheets API Errors

### Error: "Quota exceeded"

**Symptom:** Functions work for a while then start failing

**Cause:** Google Sheets API has rate limits

**Quotas:**
- 100 requests per 100 seconds per user
- 500 requests per 100 seconds per project

**Solution:**
```sql
-- Option 1: Cache data in Snowflake
CREATE OR REPLACE TABLE cached_sheet_data AS
SELECT * FROM TABLE(read_gsheet('your_id', 0));

-- Option 2: Add delay between calls
CALL SYSTEM$WAIT(1);  -- Wait 1 second

-- Option 3: Request quota increase from Google Cloud Console
```

---

### Error: Sheet is too large

**Symptom:** Function times out or fails on large sheets

**Cause:** 
- Google Sheets limited to 10M cells
- Snowflake UDF has execution time limits
- Memory constraints

**Solution:**
```sql
-- Option 1: Filter in Google Sheets first (manually)
-- Option 2: Split sheet into multiple smaller sheets
-- Option 3: Export to CSV and load into Snowflake instead
-- Option 4: Increase warehouse size for the operation
USE WAREHOUSE LARGE_WH;
```

---

## Debug Checklist

Work through this checklist systematically:

### ✓ Basic Setup
- [ ] Network rules created for both oauth2.googleapis.com and sheets.googleapis.com
- [ ] Secret created with properly escaped JSON (test with `get_gcp_email()`)
- [ ] External access integration created and links rules + secret
- [ ] Functions created successfully (no syntax errors)

### ✓ Permissions (Snowflake)
- [ ] Your role can execute the functions
- [ ] Your role has USAGE on the integration
- [ ] You're using the correct schema/database
- [ ] Warehouse is running and has appropriate size

### ✓ Permissions (Google)
- [ ] Service account email is shared on the Google Sheet
- [ ] Service account has "Editor" permission (for writes) or "Viewer" (for reads)
- [ ] You clicked "Send" in the share dialog
- [ ] The specific sheet/tab exists

### ✓ Configuration
- [ ] Spreadsheet ID is correct (from URL)
- [ ] Sheet ID is correct (tab ID, usually 0 for first tab)
- [ ] Secret name in function matches actual secret name
- [ ] Integration name in function matches actual integration name

### ✓ Network
- [ ] Your Snowflake account allows external access
- [ ] No corporate firewalls blocking googleapis.com
- [ ] Both network rules exist and are enabled

### ✓ Testing
- [ ] `get_gcp_email()` returns the service account email
- [ ] Simple read test works: `SELECT * FROM TABLE(read_gsheet('id', 0)) LIMIT 1`
- [ ] Check for error field in returned JSON
- [ ] Try with a different Google Sheet to isolate the issue

---

## Getting Help

### 1. Check Snowflake Query History
```sql
-- See detailed error messages
SELECT *
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%read_gsheet%'
ORDER BY start_time DESC
LIMIT 10;
```

### 2. Enable Detailed Logging (if available)
```sql
-- Some Snowflake accounts support detailed UDF logging
ALTER FUNCTION read_gsheet(STRING, NUMBER) 
SET LOG_LEVEL = 'DEBUG';
```

### 3. Test with Minimal Example
```sql
-- Create a test sheet with just a few rows
-- Share it with service account
-- Try reading:
SELECT * 
FROM TABLE(read_gsheet('test_sheet_id', 0))
LIMIT 5;
```

### 4. Verify JSON Parsing
```sql
-- Check if you can parse the returned data
SELECT 
    row_data,
    row_data:"column_name"::string as parsed_value
FROM TABLE(read_gsheet('your_id', 0))
LIMIT 1;
```

---

## Still Stuck?

If you've worked through this guide and still have issues:

1. **Check Snowflake documentation:** External access integrations may have changed
2. **Check Google API status:** https://status.cloud.google.com/
3. **Review function code:** The error might be in the Python code itself
4. **Contact your Snowflake admin:** They can check account-level settings
5. **Check GCP Console:** Review service account audit logs for failed auth attempts

