-- PostgreSQL AI Triage: Top Slow Queries Detector
-- Identifies slow-running queries from pg_stat_statements extension
-- Returns JSON object with detector findings
-- No superuser required if pg_stat_statements is configured

-- Ensure pg_stat_statements extension is available
-- CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

WITH slow_queries AS (
    SELECT 
        query,
        calls,
        total_exec_time,
        mean_exec_time,
        max_exec_time,
        rows
    FROM pg_stat_statements
    WHERE mean_exec_time > 1000  -- Queries with mean execution time > 1 second
        AND calls > 10            -- Queries executed more than 10 times
    ORDER BY mean_exec_time DESC
    LIMIT 10
),
query_details AS (
    SELECT 
        json_agg(
            json_build_object(
                'query', query,
                'calls', calls,
                'total_exec_time_ms', ROUND(total_exec_time::numeric, 2),
                'mean_exec_time_ms', ROUND(mean_exec_time::numeric, 2),
                'max_exec_time_ms', ROUND(max_exec_time::numeric, 2),
                'rows_returned', rows
            )
        ) AS query_list
    FROM slow_queries
)
SELECT 
    json_build_object(
        'DetectorName', 'TopSlowQueries',
        'IssueKey', 'TOP_SLOW_' || to_char(CURRENT_TIMESTAMP, 'YYYYMMDD_HH24MI'),
        'SeverityScore', CASE 
            WHEN COUNT(*) > 5 THEN 9
            WHEN COUNT(*) > 3 THEN 7
            ELSE 5
        END,
        'Summary', 'Found ' || COALESCE(COUNT(*), 0) || ' slow-running queries with mean execution time > 1 second',
        'DetailsJson', COALESCE(query_list, '[]'::json)
    ) AS detector_result
FROM slow_queries, query_details;
