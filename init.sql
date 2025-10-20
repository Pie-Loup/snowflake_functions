-- ===========================================================
-- STEP 1: Create network rules for Google APIs
-- ===========================================================

CREATE OR REPLACE NETWORK RULE google_oauth
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = ('oauth2.googleapis.com');

CREATE OR REPLACE NETWORK RULE google_sheets
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = ('sheets.googleapis.com');

-- ===========================================================
-- STEP 2: Create or update your secret with service account credentials
-- Replace <YOUR_CREDENTIALS_JSON> with the contents of your credentials.json file
-- make sure to transform the json into a one line and escape new lines
-- using $ cat service_account.json | jq -c . | sed 's/\\n/\\\\n/g'
-- or the json_escape script provided
-- ===========================================================

CREATE OR REPLACE SECRET GSHEET_CREDENTIALS
  TYPE = GENERIC_STRING
  SECRET_STRING = '<YOUR_CREDENTIALS_JSON>';


-- ===========================================================
-- STEP 3: Create or update your external access integration
-- ===========================================================

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION csv_download_integration
  ALLOWED_NETWORK_RULES = (google_oauth, google_sheets)
  ALLOWED_AUTHENTICATION_SECRETS = (GSHEET_CREDENTIALS)
  ENABLED = TRUE;

