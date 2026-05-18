-- PostgreSQL AI Triage: Dead Tuple and Vacuum Risk Detector
-- Identifies tables with high dead tuple ratios and vacuum risk
-- Returns exactly one JSON object with detector findings
-- No superuser required (uses pg_stat_user_tables)
-- Recommended: GRANT pg_read_all_stats TO triage_user;
-- Note: Detects dead tuple buildup risk, not true physical disk bloat

WITH table_stats AS (
    SELECT
        schemaname,
        relname,
        n_live_tup AS live_tup,
        n_dead_tup AS dead_tup,
        last_vacuum,
        last_autovacuum,
        n_tup_ins,
        n_tup_upd,
        n_tup_del,
        CASE
            WHEN (n_live_tup + n_dead_tup) > 0
            THEN ROUND((n_dead_tup::numeric / (n_live_tup + n_dead_tup) * 100), 2)
            ELSE 0
        END AS dead_ratio_percent,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - COALESCE(last_autovacuum, last_vacuum))) AS seconds_since_vacuum
    FROM pg_stat_user_tables
    WHERE (n_live_tup + n_dead_tup) > 1000  -- Tables with > 1000 tuples
),
vacuum_risk AS (
    SELECT
        schemaname,
        relname,
        live_tup,
        dead_tup,
        dead_ratio_percent,
        last_vacuum,
        last_autovacuum,
        seconds_since_vacuum,
        CASE
            WHEN dead_ratio_percent > 30 AND seconds_since_vacuum > 86400 THEN 'CRITICAL'
            WHEN dead_ratio_percent > 20 AND seconds_since_vacuum > 43200 THEN 'HIGH'
            WHEN dead_ratio_percent > 10 THEN 'MEDIUM'
            ELSE 'LOW'
        END AS risk_level
    FROM table_stats
    WHERE dead_ratio_percent > 10  -- Tables with > 10% dead tuples
        OR seconds_since_vacuum > 604800  -- No vacuum in 7 days
),
vacuum_summary AS (
    SELECT
        COUNT(*) AS at_risk_count,
        COUNT(*) FILTER (WHERE risk_level = 'CRITICAL') AS critical_count,
        COUNT(*) FILTER (WHERE risk_level = 'HIGH') AS high_count,
        COALESCE(
            json_agg(
                json_build_object(
                    'schema', schemaname,
                    'table', relname,
                    'live_tuples', live_tup,
                    'dead_tuples', dead_tup,
                    'dead_ratio_percent', dead_ratio_percent,
                    'risk_level', risk_level,
                    'last_vacuum', last_vacuum,
                    'seconds_since_vacuum', seconds_since_vacuum
                )
                ORDER BY dead_ratio_percent DESC
            ),
            '[]'::json
        ) AS table_list
    FROM vacuum_risk
)
SELECT
    json_build_object(
        'DetectorName', 'DeadTupleVacuumRisk',
        'IssueKey', 'VACUUM_' || to_char(CURRENT_TIMESTAMP, 'YYYYMMDD_HH24MI'),
        'SeverityScore', CASE
            WHEN critical_count > 0 THEN 10
            WHEN high_count > 0 THEN 8
            WHEN at_risk_count > 0 THEN 6
            ELSE 0
        END,
        'Summary', 'Found ' || at_risk_count || ' tables with dead tuple/vacuum risk. ' ||
                   critical_count || ' critical, ' || high_count || ' high risk',
        'DetailsJson', table_list
    ) AS detector_result
FROM vacuum_summary;
