-- ===========================================================
-- PROCEDURE: write_to_gsheet
-- ===========================================================
-- Executes a Snowflake SQL query and writes the results to a Google Sheet.
-- Data is written starting at cell A1, including column headers.
--
-- Parameters:
--   QUERY (VARCHAR)         - SQL query to execute. Results will be exported.
--   SPREADSHEET_ID (VARCHAR)- Google Sheets spreadsheet ID from URL
--   SHEET_ID (NUMBER)       - Sheet/tab ID (default: 0 for first tab)
--                             Find this in URL after 'gid='
--
-- Returns:
--   VARIANT: {"status": "success"} on success
--            {"error": "...", "error_type": "...", "spreadsheet_id": "..."} on failure
--
-- Requirements:
--   - Spreadsheet must be shared with service account email
--   - Service account needs 'Editor' permission
--   - Query must return valid tabular results
--
-- Example:
--   CALL write_to_gsheet(
--     'SELECT id, name, revenue FROM sales ORDER BY revenue DESC LIMIT 100',
--     '1abc123XYZ',
--     0
--   );
--
-- Notes:
--   - Existing data in the sheet will be overwritten starting from A1
--   - Column headers are automatically included
--   - Maximum 10 million cells per sheet (Google Sheets limit)
-- ===========================================================

CREATE OR REPLACE PROCEDURE WRITE_TO_GSHEET(
    "QUERY" VARCHAR,
    "SPREADSHEET_ID" VARCHAR, 
    "SHEET_ID" NUMBER(38,0) DEFAULT 0
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'gspread','google-auth')
EXTERNAL_ACCESS_INTEGRATIONS = (CSV_DOWNLOAD_INTEGRATION)
HANDLER = 'aggregate_query_to_list'
SECRETS = ('credential'=GSHEET_CREDENTIALS)
AS
$$
import gspread
from google.oauth2.service_account import Credentials
import _snowflake
import json

def aggregate_query_to_list(session, query, spreadsheet_id, sheet_id):
    """
    Execute Snowflake query and write results to Google Sheet.
    
    Args:
        session: Snowpark session object (automatically provided)
        query (str): SQL query to execute
        spreadsheet_id (str): Google Sheets spreadsheet ID
        sheet_id (int): Sheet/tab ID within the spreadsheet
        
    Returns:
        dict: Success status or error information
    """
    
    # Execute the SQL query using Snowpark
    df = session.sql(query)
    
    # Retrieve all rows from query results
    rows = df.collect()
    
    # Extract column names from the DataFrame schema
    column_names = df.schema.names
    
    # Build data array: first row is headers, followed by data rows
    # Convert each Row object to a list for JSON serialization
    data = [column_names] + [list(row) for row in rows]

    try:
        # Define Google API scopes for Sheets and Drive access
        SCOPES = [
            "https://spreadsheets.google.com/feeds",
            "https://www.googleapis.com/auth/drive"
        ]

        # Load service account credentials from Snowflake secret
        secret_json = _snowflake.get_generic_secret_string('credential')
        credentials = json.loads(secret_json)
        
        # Create authenticated credentials object
        creds = Credentials.from_service_account_info(credentials, scopes=SCOPES)
        
        # Initialize gspread client with credentials
        client = gspread.authorize(creds)

        # Open the Google Sheet by spreadsheet ID
        spreadsheet = client.open_by_key(spreadsheet_id)
        
        # Find the specific worksheet/tab by sheet ID
        # Sheet ID is different from sheet index - it s visible in the URL as 'gid='
        sheet = next(s for s in spreadsheet.worksheets() if s.id == sheet_id)

        # Ensure data is a Python object (list of lists), not a JSON string
        if isinstance(data, str):
            data = json.loads(data)

        # Write the data to the sheet starting from cell A1
        # This will overwrite existing data
        sheet.update(data, "A1")

        return {"status": "success"}

    except Exception as e:
        # Return structured error information for debugging
        error_info = {
            "error": str(e),
            "error_type": str(type(e).__name__),
            "spreadsheet_id": spreadsheet_id
        }
        return error_info
$$;
