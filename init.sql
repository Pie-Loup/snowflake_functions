-- ===========================================================
-- Snowflake Google Sheets Integration - Infrastructure Setup
-- ===========================================================
-- This script sets up the necessary Snowflake infrastructure to
-- enable Python UDFs to access Google Sheets via service accounts.
--
-- Prerequisites:
--   - ACCOUNTADMIN role (for integrations and network rules)
--   - SECURITYADMIN role (for secrets, or use ACCOUNTADMIN)
--   - Service account JSON file from Google Cloud Platform
--   - JSON file escaped using json_escape.py script
--
-- Security Notes:
--   - Network rules restrict access to specific Google domains only
--   - Secrets are encrypted at rest automatically
--   - External access is audited in Snowflake query history
-- ===========================================================

-- ===========================================================
-- STEP 1: Create Network Rules for Google APIs
-- ===========================================================
-- Network rules define which external endpoints Snowflake functions
-- can access. This follows the principle of least privilege.
--
-- Required role: ACCOUNTADMIN or role with CREATE NETWORK RULE privilege
-- ===========================================================

-- Allow access to Google OAuth 2.0 service
-- This is required for service account authentication
CREATE OR REPLACE NETWORK RULE google_oauth
  MODE = EGRESS                    -- Outbound traffic from Snowflake
  TYPE = HOST_PORT                 -- Specify host:port (port defaults to 443)
  VALUE_LIST = ('oauth2.googleapis.com');

-- Allow access to Google Sheets API
-- This is required for reading/writing sheet data
CREATE OR REPLACE NETWORK RULE google_sheets
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = ('sheets.googleapis.com');

-- ===========================================================
-- STEP 2: Create Secret with Service Account Credentials
-- ===========================================================
-- Secrets provide secure, encrypted storage for sensitive data.
-- The service account JSON must be escaped before storing.
--
-- Required role: ACCOUNTADMIN or SECURITYADMIN
--
-- To prepare your JSON:
--   Option 1: python3 json_escape.py service_account.json
--   Option 2: cat service_account.json | jq -c . | sed 's/\\n/\\\\n/g'
--
-- IMPORTANT: Ensure newlines in private_key are \\n (double backslash)
-- ===========================================================

CREATE OR REPLACE SECRET GSHEET_CREDENTIALS
  TYPE = GENERIC_STRING
  SECRET_STRING = '<YOUR_CREDENTIALS_JSON>';

-- ⚠️  REPLACE <YOUR_CREDENTIALS_JSON> above with your escaped JSON
-- The JSON should look like:
-- '{"type":"service_account","project_id":"...","private_key":"-----BEGIN PRIVATE KEY-----\\nMIIE...\\n-----END PRIVATE KEY-----\\n",...}'


-- ===========================================================
-- STEP 3: Create External Access Integration
-- ===========================================================
-- External Access Integration ties together network rules and secrets,
-- allowing specific functions to make external API calls.
--
-- Required role: ACCOUNTADMIN (only role that can create integrations)
--
-- This integration:
--   - Permits access to domains defined in network rules
--   - Provides access to specified secrets
--   - Can be granted to functions via EXTERNAL_ACCESS_INTEGRATIONS parameter
-- ===========================================================

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION csv_download_integration
  ALLOWED_NETWORK_RULES = (google_oauth, google_sheets)
  ALLOWED_AUTHENTICATION_SECRETS = (GSHEET_CREDENTIALS)
  ENABLED = TRUE;


-- ===========================================================
-- STEP 4: Validation (Optional but Recommended)
-- ===========================================================
-- Run these queries to verify your setup is complete
-- ===========================================================

-- Check network rules were created
SHOW NETWORK RULES LIKE 'google%';

-- Check secret was created (won't show the actual secret value)
SHOW SECRETS LIKE 'GSHEET_CREDENTIALS';

-- Check integration was created
SHOW INTEGRATIONS LIKE 'csv_download_integration';

-- View integration details
DESC INTEGRATION csv_download_integration;


-- ===========================================================
-- STEP 5: Next Steps
-- ===========================================================
-- 1. Deploy functions from read_gsheet.sql and write_gsheet.sql
-- 2. Deploy test function from test_creds.sql
-- 3. Run: SELECT get_gcp_email(); to get service account email
-- 4. Share your Google Sheet with the service account email
-- 5. Test with: SELECT * FROM TABLE(read_gsheet('your_sheet_id', 0));
-- ===========================================================


-- ===========================================================
-- CLEANUP SECTION (commented out for safety)
-- ===========================================================
-- Only run these if you need to remove the integration entirely
-- Uncomment and run in reverse order to tear down
-- ===========================================================

-- Step 1: Drop functions that use the integration
-- DROP FUNCTION IF EXISTS read_gsheet(STRING, NUMBER);
-- DROP PROCEDURE IF EXISTS write_to_gsheet(STRING, STRING, NUMBER);
-- DROP FUNCTION IF EXISTS get_gcp_email();

-- Step 2: Drop the integration
-- DROP INTEGRATION IF EXISTS csv_download_integration;

-- Step 3: Drop the secret
-- DROP SECRET IF EXISTS GSHEET_CREDENTIALS;

-- Step 4: Drop network rules
-- DROP NETWORK RULE IF EXISTS google_oauth;
-- DROP NETWORK RULE IF EXISTS google_sheets;

