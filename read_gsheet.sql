-- ===========================================================
-- FUNCTION: read_gsheet
-- ===========================================================
-- Reads data from a Google Sheet and returns each row as a VARIANT (JSON).
-- This is a table function (UDTF) that can be used in FROM clauses.
--
-- Parameters:
--   spreadsheet_id (STRING) - Google Sheets spreadsheet ID from URL
--   sheet_id (INT)          - Sheet/tab ID (default: 0 for first tab)
--                             Find this in URL after 'gid='
--
-- Returns:
--   TABLE (row_data VARIANT) - One row per Google Sheet row
--                              Each row is returned as JSON with column names as keys
--
-- Google Sheet Format Requirements:
--   - First row must contain column headers
--   - Headers become JSON keys in the returned VARIANT
--   - Empty rows may be skipped
--   - Data types are automatically inferred by gspread
--
-- Requirements:
--   - Spreadsheet must be shared with service account email
--   - Service account needs 'Viewer' or 'Editor' permission
--
-- Usage Examples:
--
--   -- Get all rows as JSON
--   SELECT * FROM TABLE(read_gsheet('1abc123XYZ', 0));
--
--   -- Parse specific columns
--   SELECT 
--     row_data:"id"::INT as id,
--     row_data:"name"::STRING as name,
--     row_data:"email"::STRING as email
--   FROM TABLE(read_gsheet('1abc123XYZ', 0));
--
--   -- Create table from sheet
--   CREATE TABLE my_data AS
--   SELECT row_data:"col1"::STRING as col1
--   FROM TABLE(read_gsheet('1abc123XYZ', 0));
--
-- Error Handling:
--   On error, returns a single row with error information:
--   {"error": "message", "error_type": "ExceptionType", "url": "spreadsheet_id"}
--
-- Notes:
--   - Uses gspread's get_all_records() which expects headers in first row
--   - Sheet must have at least one row of data (headers + 1 data row)
--   - Performance: ~2-5 seconds for sheets with < 1000 rows
-- ===========================================================

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
    """
    Table function handler class for reading Google Sheets data.
    
    Snowflake calls the process() method with the function parameters
    and expects an iterable of tuples to be returned.
    """
    
    def process(self, spreadsheet_id, sheet_id):
        """
        Read data from Google Sheet and return as rows.
        
        Args:
            spreadsheet_id (str): Google Sheets spreadsheet ID from URL
            sheet_id (int): Sheet/tab ID (visible in URL as 'gid=')
            
        Yields:
            tuple: (row_data,) where row_data is a dict with column headers as keys
            
        Returns:
            list: List of tuples on success, or list with error info on failure
        """
        try:
            # Define required Google API scopes
            # These scopes allow read access to Google Sheets and Drive
            SCOPES = [
                "https://spreadsheets.google.com/feeds",
                "https://www.googleapis.com/auth/drive"
            ]
            
            # Load service account credentials from Snowflake secret
            # 'credential' is the alias defined in the function SECRETS parameter
            secret_json = _snowflake.get_generic_secret_string('credential')
            
            # Parse JSON string to Python dictionary
            credentials = json.loads(secret_json)
            
            # Create authenticated credentials object
            creds = Credentials.from_service_account_info(credentials, scopes=SCOPES)

            # Initialize and authorize gspread client
            client = gspread.authorize(creds)
            
            # Open the spreadsheet by its unique ID
            spreadsheet = client.open_by_key(spreadsheet_id)
            
            # Find the specific worksheet/tab by sheet ID
            # Note: sheet_id is different from worksheet index
            # It's the numeric ID visible in the URL as 'gid=XXXXXX'
            sheet = next(s for s in spreadsheet.worksheets() if s.id == sheet_id)
            
            # Read all records from the sheet
            # get_all_records() expects first row to be headers
            # and returns a list of dictionaries (one per row)
            data = sheet.get_all_records()
            
            # Convert to format expected by Snowflake UDTF
            # Each row must be a tuple containing the row data
            result_to_insert = []
            for row in data:
                result_to_insert.append((row,))
            
            return result_to_insert

        except Exception as e:
            # On any error, return a single row with structured error information
            # This allows users to debug issues via SQL queries
            error_info = {
                "error": str(e),
                "error_type": str(type(e).__name__),
                "url": spreadsheet_id
            }
            return [(error_info,)]

$$;
