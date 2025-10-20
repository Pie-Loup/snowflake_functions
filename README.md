1. Create a Google Service Account and Download Credentials

Go to the Google Cloud Console
.

Navigate to IAM & Admin → Service Accounts.

Click Create Service Account.

Assign the necessary roles (e.g., access to Google Ad Manager, Google Sheets, etc.).

Go to the Keys tab → Add Key → Create new key → JSON.

Download the .json file — it contains fields like:

{
  "type": "service_account",
  "project_id": "your-project",
  "private_key_id": "abc123",
  "private_key": "-----BEGIN PRIVATE KEY-----\\nMIIEv...\\n-----END PRIVATE KEY-----\\n",
  "client_email": "service-account@your-project.iam.gserviceaccount.com"
}

🔒 2. Store the Credentials in Snowflake as a Secret

Requires SECURITYADMIN or higher:

CREATE OR REPLACE SECRET google_service_account
  TYPE = GENERIC_STRING
  SECRET_STRING = '<PASTE YOUR ENTIRE JSON STRING HERE>';


💡 Tip: You need compact your JSON to a single line before pasting, and escape new lines:
```bash
cat service_account.json | jq -c . | sed 's/\\n/\\\\n/g'
```
or use the json_escape.py script

Then call your test function
```sql
get_gcp_email();
```
this is the email you need to share the gsheet with


```sql
select *
from table(read_gsheet('gsheet_id', tab_id))
;
```

This returns a JSON per row that you can easily parse in Snowflake
```sql
select
    row_data:"id"::int as id
    , row_data:"name"::string as name
from table(read_gsheet('gsheet_id', tab_id))
;
```

You can also write data by calling the procedure

```sql
call WRITE_TO_GSHEET('
    select id, name
    from db.schema.my_table 
    '
    , 'gsheet_id'
    , tab_id
  )
;
```

If needed, you can setup a task or use it in a post hook in DBT to export data to the gsheet
