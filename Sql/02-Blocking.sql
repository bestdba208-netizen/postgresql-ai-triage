-- PostgreSQL AI Triage: Blocking Detector
-- Identifies active blocking scenarios using pg_blocking_pids()
-- Returns exactly one JSON object with detector findings
-- No superuser required; recommended: GRANT pg_read_all_stats TO triage_user;
-- Requires PostgreSQL 13+ for pg_blocking_pids() function

WITH blocking_info AS (
    SELECT DISTINCT
        a.pid,
        a.usename,
        a.query,
        a.state,
        a.query_start,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - a.query_start)) AS query_duration_seconds,
        CASE
            WHEN pg_blocking_pids(a.pid)::text != '{}' THEN 'blocked'
            ELSE 'blocking'
        END AS role,
        pg_blocking_pids(a.pid) AS blocked_by_pids
    FROM pg_stat_activity a
    WHERE (
        pg_blocking_pids(a.pid)::text != '{}'
        OR a.pid IN (
            SELECT unnest(pg_blocking_pids(pid))
            FROM pg_stat_activity
            WHERE pg_blocking_pids(pid)::text != '{}'
        )
    )
    AND a.pid <> pg_backend_pid()
),
blocking_summary AS (
    SELECT
        COUNT(*) AS blocking_count,
        COALESCE(
            json_agg(
                json_build_object(
                    'pid', pid,
                    'user', usename,
                    'query', LEFT(query, 200),
                    'state', state,
                    'query_start', query_start,
                    'duration_seconds', query_duration_seconds,
                    'role', role,
                    'blocked_by_pids', blocked_by_pids
                )
                ORDER BY query_duration_seconds DESC
            ),
            '[]'::json
        ) AS blocking_list
    FROM blocking_info
)
SELECT
    json_build_object(
        'DetectorName', 'Blocking',
        'IssueKey', 'BLOCK_' || to_char(CURRENT_TIMESTAMP, 'YYYYMMDD_HH24MI'),
        'SeverityScore', CASE
            WHEN blocking_count > 5 THEN 10
            WHEN blocking_count > 2 THEN 8
            WHEN blocking_count > 0 THEN 6
            ELSE 0
        END,
        'Summary', 'Found ' || blocking_count || ' active blocking scenarios',
        'DetailsJson', blocking_list
    ) AS detector_result
FROM blocking_summary;
