-- PostgreSQL AI Triage: Blocking Detector
-- Identifies active blocking scenarios using pg_blocking_pids()
-- Returns exactly one JSON object with detector findings
-- No superuser required; recommended: GRANT pg_read_all_stats TO triage_user;
-- Requires PostgreSQL 13+ for pg_blocking_pids() function

WITH blocked_sessions AS (
    SELECT
        a.pid AS waiter_pid,
        a.usename AS waiter_user,
        a.query AS waiter_query,
        a.state AS waiter_state,
        a.query_start AS waiter_query_start,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - a.query_start)) AS waiter_duration_seconds,
        pg_blocking_pids(a.pid) AS blocker_pids
    FROM pg_stat_activity a
    WHERE cardinality(pg_blocking_pids(a.pid)) > 0
      AND a.pid <> pg_backend_pid()
),
waiter_blocker_pairs AS (
    SELECT
        waiter_pid,
        waiter_user,
        waiter_query,
        waiter_state,
        waiter_query_start,
        waiter_duration_seconds,
        unnest(blocker_pids) AS blocker_pid
    FROM blocked_sessions
),
blocker_details AS (
    SELECT
        wb.waiter_pid,
        wb.waiter_user,
        wb.waiter_query,
        wb.waiter_state,
        wb.waiter_query_start,
        wb.waiter_duration_seconds,
        wb.blocker_pid,
        pb.usename AS blocker_user,
        LEFT(pb.query, 200) AS blocker_query,
        pb.state AS blocker_state
    FROM waiter_blocker_pairs wb
    LEFT JOIN pg_stat_activity pb ON pb.pid = wb.blocker_pid
),
blocking_summary AS (
    SELECT
        COUNT(DISTINCT waiter_pid) AS blocking_count,
        COALESCE(
            json_agg(
                json_build_object(
                    'waiter_pid', waiter_pid,
                    'waiter_user', waiter_user,
                    'waiter_query', LEFT(waiter_query, 200),
                    'waiter_state', waiter_state,
                    'waiter_query_start', waiter_query_start,
                    'waiter_duration_seconds', waiter_duration_seconds,
                    'blocker_pid', blocker_pid,
                    'blocker_user', blocker_user,
                    'blocker_query', blocker_query,
                    'blocker_state', blocker_state
                )
                ORDER BY waiter_duration_seconds DESC
            ),
            '[]'::json
        ) AS blocking_list
    FROM blocker_details
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
        'Summary', 'Found ' || blocking_count || ' active waiting/blocking session relationships',
        'DetailsJson', blocking_list
    ) AS detector_result
FROM blocking_summary;
