CREATE OR REPLACE FUNCTION read_gsheet(spreadsheet_id STRING, sheet_id INT DEFAULT 0)
  RETURNS TABLE (row_data VARIANT)
  LANGUAGE PYTHON
  RUNTIME_VERSION = '3.11'
  HANDLER = 'CSVReader'
  EXTERNAL_ACCESS_INTEGRATIONS = (csv_download_integration)
  SECRETS = ('credential'= GSHEET_CREDENTIALS)
  PACKAGES = ('gspread', 'google-auth')
AS $$
import gspread
from google.oauth2.service_account import Credentials
import _snowflake
import json
class CSVReader:
    def process(self, spreadsheet_id, sheet_id):
        try:

            # Define the scope
            SCOPES = ["https://spreadsheets.google.com/feeds", "https://www.googleapis.com/auth/drive"]
            
            # Load credentials
            secret_json = _snowflake.get_generic_secret_string('credential')
            
            # Convert JSON string to dictionary
            credentials = json.loads(secret_json)
            creds = Credentials.from_service_account_info(credentials, scopes=SCOPES)

            # Authorize with gspread
            client = gspread.authorize(creds)
            
            # Open the Google Sheet (by id)
            spreadsheet = client.open_by_key(spreadsheet_id)
            sheet = next(s for s in spreadsheet.worksheets() if s.id == sheet_id)
            
            # Read all values
            data = sheet.get_all_records()
            
            result_to_insert = []
            for row in data:
                result_to_insert.append((row,))
            
            return result_to_insert

        except Exception as e:
            error_info = {
                "error": str(e),
                "error_type": str(type(e).__name__),
                "url": spreadsheet_id
            }
            return [(error_info,)]

$$;
