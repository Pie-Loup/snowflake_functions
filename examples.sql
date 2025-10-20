-- ===========================================================
-- Snowflake Google Sheets Integration - Usage Examples
-- ===========================================================
-- This file contains practical examples of using the read_gsheet
-- and write_to_gsheet functions in various scenarios.
--
-- Note: Replace 'YOUR_SPREADSHEET_ID' and sheet IDs with your actual values
-- ===========================================================


-- ===========================================================
-- SECTION 1: Basic Reading Examples
-- ===========================================================

-- Example 1.1: Read all data from a Google Sheet
SELECT * 
FROM TABLE(read_gsheet('YOUR_SPREADSHEET_ID', 0))
LIMIT 10;


-- Example 1.2: Parse JSON columns into typed columns
SELECT 
    row_data:"id"::INT as id,
    row_data:"name"::STRING as name,
    row_data:"email"::STRING as email,
    row_data:"created_date"::DATE as created_date,
    row_data:"is_active"::BOOLEAN as is_active,
    row_data:"revenue"::FLOAT as revenue
FROM TABLE(read_gsheet('YOUR_SPREADSHEET_ID', 0));


-- Example 1.3: Filter data after reading
SELECT 
    row_data:"product_id"::INT as product_id,
    row_data:"product_name"::STRING as product_name,
    row_data:"price"::FLOAT as price
FROM TABLE(read_gsheet('YOUR_SPREADSHEET_ID', 0))
WHERE row_data:"price"::FLOAT > 100
ORDER BY row_data:"price"::FLOAT DESC;


-- Example 1.4: Aggregate data from Google Sheets
SELECT 
    row_data:"category"::STRING as category,
    COUNT(*) as item_count,
    SUM(row_data:"amount"::FLOAT) as total_amount,
    AVG(row_data:"amount"::FLOAT) as avg_amount
FROM TABLE(read_gsheet('YOUR_SPREADSHEET_ID', 0))
GROUP BY row_data:"category"::STRING
ORDER BY total_amount DESC;


-- Example 1.5: Read from specific tab (not the first one)
-- Find sheet ID in URL: https://docs.google.com/spreadsheets/d/SPREADSHEET_ID/edit#gid=SHEET_ID
SELECT * 
FROM TABLE(read_gsheet('YOUR_SPREADSHEET_ID', 123456))  -- Replace 123456 with actual sheet ID
LIMIT 10;


-- ===========================================================
-- SECTION 2: Creating Tables from Google Sheets
-- ===========================================================

-- Example 2.1: Create a permanent table from Google Sheets data
CREATE OR REPLACE TABLE reference_data AS
SELECT 
    row_data:"id"::INT as id,
    row_data:"name"::STRING as name,
    row_data:"description"::STRING as description,
    row_data:"value"::FLOAT as value,
    CURRENT_TIMESTAMP() as loaded_at
FROM TABLE(read_gsheet('YOUR_SPREADSHEET_ID', 0));


-- Example 2.2: Create a transient table for temporary analysis
CREATE OR REPLACE TRANSIENT TABLE temp_import AS
SELECT 
    row_data:"customer_id"::INT as customer_id,
    row_data:"segment"::STRING as segment
FROM TABLE(read_gsheet('YOUR_SPREADSHEET_ID', 0));


-- Example 2.3: Incremental load pattern (upsert)
MERGE INTO target_table t
USING (
    SELECT 
        row_data:"id"::INT as id,
        row_data:"value"::STRING as value,
        row_data:"updated_date"::DATE as updated_date
    FROM TABLE(read_gsheet('YOUR_SPREADSHEET_ID', 0))
) s
ON t.id = s.id
WHEN MATCHED THEN 
    UPDATE SET 
        t.value = s.value,
        t.updated_date = s.updated_date,
        t.last_modified = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN
    INSERT (id, value, updated_date, last_modified)
    VALUES (s.id, s.value, s.updated_date, CURRENT_TIMESTAMP());


-- ===========================================================
-- SECTION 3: Joining with Existing Tables
-- ===========================================================

-- Example 3.1: Join Google Sheets data with Snowflake table
SELECT 
    o.order_id,
    o.product_id,
    o.quantity,
    p.row_data:"product_name"::STRING as product_name,
    p.row_data:"category"::STRING as category,
    p.row_data:"unit_price"::FLOAT as unit_price,
    o.quantity * p.row_data:"unit_price"::FLOAT as line_total
FROM orders o
JOIN TABLE(read_gsheet('YOUR_SPREADSHEET_ID', 0)) p
    ON o.product_id = p.row_data:"product_id"::INT
WHERE o.order_date >= CURRENT_DATE() - 30;


-- Example 3.2: Left join to enrich Snowflake data with Sheet data
SELECT 
    c.customer_id,
    c.customer_name,
    c.email,
    COALESCE(s.row_data:"segment"::STRING, 'Unclassified') as segment,
    s.row_data:"priority"::STRING as priority
FROM customers c
LEFT JOIN TABLE(read_gsheet('YOUR_SPREADSHEET_ID', 0)) s
    ON c.customer_id = s.row_data:"customer_id"::INT;


-- Example 3.3: Use Google Sheets as a filter
-- Only process records that exist in the Google Sheet
SELECT 
    t.*
FROM transactions t
WHERE t.transaction_id IN (
    SELECT row_data:"transaction_id"::INT
    FROM TABLE(read_gsheet('YOUR_SPREADSHEET_ID', 0))
);


-- ===========================================================
-- SECTION 4: Basic Writing Examples
-- ===========================================================

-- Example 4.1: Export query results to Google Sheets
CALL write_to_gsheet(
    'SELECT customer_id, name, email, total_purchases 
     FROM customer_summary 
     ORDER BY total_purchases DESC 
     LIMIT 100',
    'YOUR_SPREADSHEET_ID',
    0
);


-- Example 4.2: Export aggregated data
CALL write_to_gsheet(
    'SELECT 
        DATE_TRUNC(''month'', order_date) as month,
        COUNT(*) as order_count,
        SUM(order_amount) as total_revenue,
        AVG(order_amount) as avg_order_value
     FROM orders
     WHERE order_date >= DATEADD(month, -12, CURRENT_DATE())
     GROUP BY 1
     ORDER BY 1',
    'YOUR_SPREADSHEET_ID',
    0
);


-- Example 4.3: Export to different tabs of the same spreadsheet
-- Export summary to first tab
CALL write_to_gsheet(
    'SELECT region, SUM(sales) as total_sales FROM sales_data GROUP BY region',
    'YOUR_SPREADSHEET_ID',
    0  -- First tab
);

-- Export details to second tab (find sheet ID in URL after gid=)
CALL write_to_gsheet(
    'SELECT * FROM sales_data WHERE region = ''North America''',
    'YOUR_SPREADSHEET_ID',
    123456  -- Second tab sheet ID
);


-- Example 4.4: Export with formatted columns
CALL write_to_gsheet(
    'SELECT 
        product_name,
        TO_CHAR(revenue, ''$999,999,999.99'') as revenue_formatted,
        ROUND(profit_margin * 100, 2) || ''%'' as profit_margin_pct,
        TO_VARCHAR(last_updated, ''YYYY-MM-DD HH24:MI'') as last_updated
     FROM product_metrics',
    'YOUR_SPREADSHEET_ID',
    0
);


-- ===========================================================
-- SECTION 5: Advanced Patterns
-- ===========================================================

-- Example 5.1: Scheduled daily export using Snowflake Tasks
CREATE OR REPLACE TASK daily_metrics_export
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = 'USING CRON 0 6 * * * UTC'  -- Daily at 6 AM UTC
AS
  CALL write_to_gsheet(
    'SELECT 
        CURRENT_DATE() as report_date,
        metric_name,
        metric_value,
        TO_VARCHAR(CURRENT_TIMESTAMP(), ''YYYY-MM-DD HH24:MI:SS'') as generated_at
     FROM daily_metrics 
     WHERE metric_date = CURRENT_DATE()',
    'YOUR_SPREADSHEET_ID',
    0
  );

-- Enable the task
ALTER TASK daily_metrics_export RESUME;

-- View task history
-- SELECT * FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY()) WHERE NAME = 'DAILY_METRICS_EXPORT' ORDER BY SCHEDULED_TIME DESC LIMIT 10;


-- Example 5.2: Export large dataset in batches
-- For sheets with > 10 million cells, split into multiple tabs
CALL write_to_gsheet(
    'SELECT * FROM large_table WHERE region = ''North'' LIMIT 100000',
    'YOUR_SPREADSHEET_ID',
    0
);

CALL write_to_gsheet(
    'SELECT * FROM large_table WHERE region = ''South'' LIMIT 100000',
    'YOUR_SPREADSHEET_ID',
    111111
);

CALL write_to_gsheet(
    'SELECT * FROM large_table WHERE region = ''East'' LIMIT 100000',
    'YOUR_SPREADSHEET_ID',
    222222
);


-- Example 5.3: Conditional export using stored procedure
CREATE OR REPLACE PROCEDURE conditional_export(threshold FLOAT)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    record_count INT;
BEGIN
    -- Count records that meet threshold
    SELECT COUNT(*) INTO :record_count 
    FROM alert_data 
    WHERE value > :threshold;
    
    -- Only export if there are records
    IF (record_count > 0) THEN
        CALL write_to_gsheet(
            'SELECT * FROM alert_data WHERE value > ' || :threshold || ' ORDER BY value DESC',
            'YOUR_SPREADSHEET_ID',
            0
        );
        RETURN 'Exported ' || record_count || ' records';
    ELSE
        RETURN 'No records to export';
    END IF;
END;
$$;

-- Usage:
-- CALL conditional_export(1000);


-- Example 5.4: Error handling pattern
CREATE OR REPLACE PROCEDURE safe_export(query_text STRING, sheet_id STRING, tab_id INT)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
AS
$$
try {
    var result = snowflake.execute({
        sqlText: `CALL write_to_gsheet('${QUERY_TEXT}', '${SHEET_ID}', ${TAB_ID})`
    });
    result.next();
    return result.getColumnValue(1);
} catch (err) {
    return {
        status: 'error',
        message: err.message,
        query: QUERY_TEXT
    };
}
$$;


-- ===========================================================
-- SECTION 6: Integration with dbt
-- ===========================================================

-- Example 6.1: dbt post-hook to export model results
-- Add this to your dbt model's config:
/*
{{ config(
    materialized='table',
    post_hook=[
        "CALL write_to_gsheet('SELECT * FROM {{ this }}', 'YOUR_SPREADSHEET_ID', 0)"
    ]
) }}
*/


-- Example 6.2: dbt post-hook with conditional export
-- Only export if row count exceeds threshold
/*
{{ config(
    post_hook=[
        "{% if execute and (this | row_count) > 0 %}
         CALL write_to_gsheet('SELECT * FROM {{ this }} LIMIT 1000', 'YOUR_SPREADSHEET_ID', 0)
         {% endif %}"
    ]
) }}
*/


-- ===========================================================
-- SECTION 7: Monitoring and Debugging
-- ===========================================================

-- Example 7.1: Check for errors in read operations
SELECT 
    CASE 
        WHEN row_data:"error" IS NOT NULL THEN 'ERROR'
        ELSE 'SUCCESS'
    END as status,
    row_data:"error"::STRING as error_message,
    row_data:"error_type"::STRING as error_type,
    row_data
FROM TABLE(read_gsheet('YOUR_SPREADSHEET_ID', 0))
LIMIT 5;


-- Example 7.2: View recent Google Sheets operations
SELECT 
    query_text,
    start_time,
    end_time,
    DATEDIFF(second, start_time, end_time) as duration_seconds,
    total_elapsed_time / 1000 as elapsed_seconds,
    rows_produced,
    error_message
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%read_gsheet%' OR query_text ILIKE '%write_to_gsheet%'
ORDER BY start_time DESC
LIMIT 20;


-- Example 7.3: Validate sheet data completeness
SELECT 
    COUNT(*) as row_count,
    COUNT(row_data:"id") as id_count,
    COUNT(DISTINCT row_data:"id") as unique_id_count,
    COUNT(*) - COUNT(row_data:"id") as missing_ids
FROM TABLE(read_gsheet('YOUR_SPREADSHEET_ID', 0));


-- Example 7.4: Compare Google Sheets data with Snowflake table
WITH sheet_data AS (
    SELECT 
        row_data:"id"::INT as id,
        row_data:"value"::STRING as value
    FROM TABLE(read_gsheet('YOUR_SPREADSHEET_ID', 0))
),
sf_data AS (
    SELECT id, value FROM your_table
)
SELECT 
    COALESCE(s.id, t.id) as id,
    s.value as sheet_value,
    t.value as snowflake_value,
    CASE 
        WHEN s.id IS NULL THEN 'Missing in Sheet'
        WHEN t.id IS NULL THEN 'Missing in Snowflake'
        WHEN s.value <> t.value THEN 'Value Mismatch'
        ELSE 'Match'
    END as status
FROM sheet_data s
FULL OUTER JOIN sf_data t ON s.id = t.id
WHERE s.value <> t.value OR s.id IS NULL OR t.id IS NULL;


-- ===========================================================
-- SECTION 8: Performance Optimization
-- ===========================================================

-- Example 8.1: Cache frequently accessed sheet data
CREATE OR REPLACE TABLE cached_sheet_data AS
SELECT 
    row_data:"id"::INT as id,
    row_data:"name"::STRING as name,
    row_data:"value"::FLOAT as value,
    CURRENT_TIMESTAMP() as cached_at
FROM TABLE(read_gsheet('YOUR_SPREADSHEET_ID', 0));

-- Refresh cache periodically with a task
CREATE OR REPLACE TASK refresh_sheet_cache
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = 'USING CRON 0 */4 * * * UTC'  -- Every 4 hours
AS
  CREATE OR REPLACE TABLE cached_sheet_data AS
  SELECT 
      row_data:"id"::INT as id,
      row_data:"name"::STRING as name,
      row_data:"value"::FLOAT as value,
      CURRENT_TIMESTAMP() as cached_at
  FROM TABLE(read_gsheet('YOUR_SPREADSHEET_ID', 0));


-- Example 8.2: Use smaller warehouse for sheet operations
-- Google Sheets API is the bottleneck, not compute
USE WAREHOUSE XSMALL_WH;  -- Smaller warehouse is sufficient

SELECT * FROM TABLE(read_gsheet('YOUR_SPREADSHEET_ID', 0));


-- Example 8.3: Limit exported data size
-- Google Sheets has 10M cell limit
-- For a 100-column table: max ~100,000 rows
CALL write_to_gsheet(
    'SELECT * FROM large_table 
     WHERE created_date >= DATEADD(day, -30, CURRENT_DATE())
     LIMIT 50000',  -- Reasonable limit
    'YOUR_SPREADSHEET_ID',
    0
);


-- ===========================================================
-- SECTION 9: Security Patterns
-- ===========================================================

-- Example 9.1: Grant execute permissions to specific roles
GRANT USAGE ON FUNCTION read_gsheet(STRING, NUMBER) TO ROLE analyst_role;
GRANT USAGE ON PROCEDURE write_to_gsheet(STRING, STRING, NUMBER) TO ROLE etl_role;


-- Example 9.2: Create wrapper view to restrict access
CREATE OR REPLACE SECURE VIEW public_metrics AS
SELECT 
    row_data:"metric_name"::STRING as metric_name,
    row_data:"metric_value"::FLOAT as metric_value,
    row_data:"report_date"::DATE as report_date
FROM TABLE(read_gsheet('YOUR_SPREADSHEET_ID', 0))
WHERE row_data:"is_public"::BOOLEAN = TRUE;

-- Grant view access instead of direct function access
GRANT SELECT ON VIEW public_metrics TO ROLE public_role;


-- Example 9.3: Audit function usage
SELECT 
    user_name,
    role_name,
    query_text,
    start_time,
    rows_produced,
    CASE 
        WHEN query_text ILIKE '%write_to_gsheet%' THEN 'WRITE'
        WHEN query_text ILIKE '%read_gsheet%' THEN 'READ'
    END as operation_type
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%gsheet%'
  AND start_time >= DATEADD(day, -7, CURRENT_DATE())
ORDER BY start_time DESC;


-- ===========================================================
-- SECTION 10: Tips and Best Practices
-- ===========================================================

/*

TIPS:
1. Always test with LIMIT before exporting large datasets
2. Use smaller warehouses (XS/S) - API latency is the bottleneck, not compute
3. Cache frequently accessed sheets in Snowflake tables
4. Monitor Google Sheets API quotas (100 requests per 100 seconds)
5. Use tasks for scheduled exports rather than manual runs
6. Add timestamps to exported data for audit trail
7. Consider using views to standardize sheet parsing logic

BEST PRACTICES:
1. Name columns clearly in your sheets - they become JSON keys
2. Keep first row as headers only (no merged cells)
3. Avoid formulas in cells that will be read by Snowflake
4. Use separate sheets/tabs for different data domains
5. Document which sheets are integrated with Snowflake
6. Set up Google Sheet permissions carefully
7. Rotate service account keys regularly
8. Monitor failed operations via query history

COMMON PITFALLS:
1. Forgetting to share sheet with service account email
2. Using wrong sheet ID (use gid= from URL, not tab position)
3. Not escaping JSON properly when creating secret
4. Exceeding 10M cell limit in Google Sheets
5. Not handling errors returned in VARIANT
6. Running large exports on oversized warehouses

*/

