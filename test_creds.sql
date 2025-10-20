-- ===========================================================
-- TEST FUNCTION: Verify Google Service Account Configuration
-- ===========================================================
-- This function tests your Snowflake secret configuration by
-- extracting and returning the service account email.
--
-- Usage:
--   SELECT get_gcp_email();
--
-- Expected output:
--   service-account-name@project-id.iam.gserviceaccount.com
--
-- If this fails, your secret is not properly configured.
-- ===========================================================

CREATE OR REPLACE FUNCTION get_gcp_email()
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
HANDLER = 'main'
SECRETS = ('credential' = GSHEET_CREDENTIALS)  -- Use same secret as production functions
EXTERNAL_ACCESS_INTEGRATIONS = (csv_download_integration)
PACKAGES = ('google-auth')
AS
$$
import json
from google.oauth2.service_account import Credentials
import _snowflake

def main():
    """
    Test function to verify Google Cloud credentials configuration.
    
    This function:
    1. Retrieves the service account JSON from Snowflake secret
    2. Parses and validates the JSON structure
    3. Creates GCP credentials object
    4. Extracts and returns the service account email
    
    Returns:
        str: Service account email address
        
    Raises:
        ValueError: If secret JSON is malformed
        KeyError: If required fields are missing from JSON
    """
    
    # Fetch the secret from Snowflake
    # 'credential' is the alias defined in the SECRETS parameter above
    secret_json = _snowflake.get_generic_secret_string('credential')
    
    # Parse JSON string to Python dictionary
    credentials_dict = json.loads(secret_json)
    
    # Define required Google API scopes
    # These scopes allow read/write access to Google Sheets and Drive
    SCOPES = [
        "https://spreadsheets.google.com/feeds",
        "https://www.googleapis.com/auth/drive"
    ]
    
    # Create credentials object from service account info
    # This validates the private key format and structure
    creds = Credentials.from_service_account_info(credentials_dict, scopes=SCOPES)
    
    # Extract and return the service account email
    # This is the email you need to share Google Sheets with
    email = creds._service_account_email
    
    return email
$$;
