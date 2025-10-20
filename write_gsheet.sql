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
    
    # Run the query using the Snowpark API.
    df = session.sql(query)
    
    # Retrieve all rows as a list.
    rows = df.collect()
    
    # Get the column names from the DataFrame schema.
    column_names = df.schema.names
    
    # Convert each row (which is a Row object) to a list and aggregate with column names.
    data = [column_names] + [list(row) for row in rows]
    
    # Return the aggregated list of lists.

    try:
        # Définir les scopes
        SCOPES = ["https://spreadsheets.google.com/feeds", "https://www.googleapis.com/auth/drive"]

        # Charger les credentials depuis le secret
        secret_json = _snowflake.get_generic_secret_string('credential')
        credentials = json.loads(secret_json)
        creds = Credentials.from_service_account_info(credentials, scopes=SCOPES)
        client = gspread.authorize(creds)

        # Ouvrir la Google Sheet par ID
        spreadsheet = client.open_by_key(spreadsheet_id)
        sheet = next(s for s in spreadsheet.worksheets() if s.id == sheet_id)

        # Check DATA is a Python object (e.g., a list of lists)
        if isinstance(data, str):
            data = json.loads(data)

        # Write the data starting from cell A1
        sheet.update(data, "A1")

        return {"status": "success"}

    except Exception as e:
        error_info = {
            "error": str(e),
            "error_type": str(type(e).__name__),
            "spreadsheet_id": spreadsheet_id
        }
        return error_info
$$;
