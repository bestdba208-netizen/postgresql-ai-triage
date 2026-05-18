-- PostgreSQL AI Triage: Table Bloat and Vacuum Risk Detector
-- Identifies tables with high dead tuple ratios and vacuum risk
-- Returns JSON object with detector findings
-- No superuser required (uses pg_stat_user_tables)

WITH table_stats AS (
    SELECT 
        schemaname,
        relname,
        live_tup,
        dead_tup,
        last_vacuum,
        last_autovacuum,
        n_tup_ins,
        n_tup_upd,
        n_tup_del,
        CASE 
            WHEN (live_tup + dead_tup) > 0 
            THEN ROUND((dead_tup::numeric / (live_tup + dead_tup) * 100), 2)
            ELSE 0
        END AS dead_ratio_percent,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - COALESCE(last_autovacuum, last_vacuum))) AS seconds_since_vacuum
    FROM pg_stat_user_tables
    WHERE (live_tup + dead_tup) > 1000  -- Tables with > 1000 tuples
),
bloat_risk AS (
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
bloat_summary AS (
    SELECT 
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
            ) ORDER BY dead_ratio_percent DESC
        ) AS table_list
    FROM bloat_risk
)
SELECT 
    json_build_object(
        'DetectorName', 'TableBloatVacuumRisk',
        'IssueKey', 'BLOAT_' || to_char(CURRENT_TIMESTAMP, 'YYYYMMDD_HH24MI'),
        'SeverityScore', CASE 
            WHEN COUNT(*) FILTER (WHERE risk_level = 'CRITICAL') > 0 THEN 10
            WHEN COUNT(*) FILTER (WHERE risk_level = 'HIGH') > 0 THEN 8
            WHEN COUNT(*) FILTER (WHERE risk_level = 'MEDIUM') > 0 THEN 6
            ELSE 3
        END,
        'Summary', 'Found ' || COALESCE(COUNT(*), 0) || ' tables with bloat/vacuum risk. ' ||
                   COALESCE(COUNT(*) FILTER (WHERE risk_level = 'CRITICAL'), 0) || ' critical, ' ||
                   COALESCE(COUNT(*) FILTER (WHERE risk_level = 'HIGH'), 0) || ' high risk',
        'DetailsJson', COALESCE(table_list, '[]'::json)
    ) AS detector_result
FROM bloat_risk, bloat_summary;
