CREATE OR REPLACE FUNCTION get_gcp_email()
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
HANDLER = 'main'
SECRETS = ('credential'= GSHEET_CREDENTIALS_TEST)
EXTERNAL_ACCESS_INTEGRATIONS = (csv_download_integration)
PACKAGES = ('google-auth')
AS
$$
import json
from google.oauth2.service_account import Credentials
import _snowflake

def main():

    # Fetch the key
    secret_json = _snowflake.get_generic_secret_string('credential')
    
    # Convert JSON string to dictionary
    credentials_dict = json.loads(secret_json)
    

    # Use from_service_account_info() with corrected private key
    SCOPES = ["https://spreadsheets.google.com/feeds", "https://www.googleapis.com/auth/drive"]
    creds = Credentials.from_service_account_info(credentials_dict, scopes=SCOPES)

    # extract the email
    email = creds._service_account_email
    
    return email
$$;
