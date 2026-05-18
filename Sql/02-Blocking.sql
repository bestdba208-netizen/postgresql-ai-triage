-- PostgreSQL AI Triage: Blocking Detector
-- Identifies active blocking scenarios from pg_stat_activity and pg_locks
-- Returns JSON object with detector findings
-- No superuser required

WITH blocking_pids AS (
    SELECT 
        pid,
        usename,
        query,
        state,
        query_start,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - query_start)) AS query_duration_seconds
    FROM pg_stat_activity
    WHERE pid <> pg_backend_pid()
        AND state IS NOT NULL
),
lock_info AS (
    SELECT 
        l.pid,
        a.usename,
        a.query,
        a.state,
        a.query_start,
        a.query_duration_seconds,
        COUNT(DISTINCT l.locktype) AS lock_count,
        STRING_AGG(DISTINCT l.locktype, ', ') AS lock_types
    FROM pg_locks l
    JOIN blocking_pids a ON l.pid = a.pid
    WHERE NOT l.granted
    GROUP BY l.pid, a.usename, a.query, a.state, a.query_start, a.query_duration_seconds
),
blocking_details AS (
    SELECT 
        json_agg(
            json_build_object(
                'pid', pid,
                'user', usename,
                'query', LEFT(query, 200),
                'state', state,
                'query_start', query_start,
                'duration_seconds', query_duration_seconds,
                'lock_types', lock_types
            )
        ) AS lock_list
    FROM lock_info
)
SELECT 
    json_build_object(
        'DetectorName', 'Blocking',
        'IssueKey', 'BLOCK_' || to_char(CURRENT_TIMESTAMP, 'YYYYMMDD_HH24MI'),
        'SeverityScore', CASE 
            WHEN COUNT(*) > 5 THEN 10
            WHEN COUNT(*) > 2 THEN 8
            WHEN COUNT(*) > 0 THEN 6
            ELSE 0
        END,
        'Summary', 'Found ' || COALESCE(COUNT(*), 0) || ' active blocking locks',
        'DetailsJson', COALESCE(lock_list, '[]'::json)
    ) AS detector_result
FROM lock_info, blocking_details;
