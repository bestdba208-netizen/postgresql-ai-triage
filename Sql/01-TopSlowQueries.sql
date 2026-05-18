-- PostgreSQL AI Triage: Top Slow Queries Detector
-- Identifies slow-running queries from pg_stat_statements extension
-- Returns exactly one JSON object with detector findings
-- No superuser required if pg_stat_statements is configured
-- Recommended: GRANT pg_read_all_stats TO triage_user;

WITH slow_queries AS (
    SELECT
        queryid,
        query,
        calls,
        total_exec_time,
        mean_exec_time,
        max_exec_time,
        rows,
        shared_blks_hit,
        shared_blks_read,
        temp_blks_written
    FROM pg_stat_statements
    WHERE mean_exec_time > 1000  -- Queries with mean execution time > 1 second
        AND calls > 10            -- Queries executed more than 10 times
    ORDER BY mean_exec_time DESC
    LIMIT 10
),
aggregated AS (
    SELECT
        COUNT(*) AS query_count,
        COALESCE(
            json_agg(
                json_build_object(
                    'queryid', queryid,
                    'query', query,
                    'calls', calls,
                    'total_exec_time_ms', ROUND(total_exec_time::numeric, 2),
                    'mean_exec_time_ms', ROUND(mean_exec_time::numeric, 2),
                    'max_exec_time_ms', ROUND(max_exec_time::numeric, 2),
                    'rows', rows,
                    'shared_blks_hit', shared_blks_hit,
                    'shared_blks_read', shared_blks_read,
                    'temp_blks_written', temp_blks_written
                )
                ORDER BY mean_exec_time DESC
            ),
            '[]'::json
        ) AS query_list
    FROM slow_queries
)
SELECT
    json_build_object(
        'DetectorName', 'TopSlowQueries',
        'IssueKey', 'TOP_SLOW_' || to_char(CURRENT_TIMESTAMP, 'YYYYMMDD_HH24MI'),
        'SeverityScore', CASE
            WHEN query_count > 5 THEN 9
            WHEN query_count > 3 THEN 7
            WHEN query_count > 0 THEN 5
            ELSE 0
        END,
        'Summary', 'Found ' || query_count || ' slow-running queries with mean execution time > 1 second',
        'DetailsJson', query_list
    ) AS detector_result
FROM aggregated;
