# PostgreSQL AI Triage

Automated PostgreSQL health checks and performance diagnostics using AI-driven triage.

## Overview

PostgreSQL AI Triage is an MVP tool that identifies and reports performance issues and configuration risks in PostgreSQL databases. It runs a set of detector queries to analyze:

- **Slow Running Queries**: Queries with high execution time and frequent runs
- **Blocking Locks**: Active session blocking detected via pg_blocking_pids()
- **Dead Tuple & Vacuum Risk**: Tables with high dead tuple ratios requiring vacuum attention

Each detector returns structured JSON output for easy parsing and integration.

## Features

- ✅ Non-superuser friendly (uses `pg_stat_*` views)
- ✅ Recommended: `pg_read_all_stats` role for full visibility
- ✅ JSON output for each detector
- ✅ Severity scoring (0-10 scale)
- ✅ Comprehensive logging and reporting
- ✅ Timestamp-based result organization
- ✅ PowerShell-based orchestration

## Directory Structure

```
postgresql-ai-triage/
├── Sql/                          # Detector SQL scripts
│   ├── 01-TopSlowQueries.sql
│   ├── 02-Blocking.sql
│   └── 03-DeadTupleVacuumRisk.sql
├── Scripts/                      # PowerShell orchestration
│   └── Invoke-PostgresAiTriage.ps1
├── Reports/                      # Full JSON reports (generated)
├── Logs/                         # Execution logs (generated)
├── History/                      # Summary reports (generated)
└── README.md
```

## Prerequisites

### Required
- PowerShell 5.1+
- `psql` (PostgreSQL client) in PATH
- Network access to PostgreSQL database
- Basic SELECT permissions on system catalogs

### Recommended
- PostgreSQL 13+ (for `pg_blocking_pids()` support)
- `pg_read_all_stats` role granted for full visibility into other sessions
- `pg_stat_statements` extension enabled for slow query detection

### Optional Setup (for superuser)
```sql
-- Enable pg_stat_statements
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Grant triage user read access to all statistics
GRANT pg_read_all_stats TO triage_user;
```

## Usage

###PgHost localhost `
  -Database mydb `
  -Username postgres `
  -Port 5432
```

### With Password

```powershell
.\Scripts\Invoke-PostgresAiTriage.ps1 `
  -PgHost localhost `
  -Database mydb `
  -Username postgres `
  -Port 5432 `
  -Password "mypassword"
```

### Custom Output Paths

```powershell
.\Scripts\Invoke-PostgresAiTriage.ps1 `
  -Pg Custom Output Paths

```powershell
.\Scripts\Invoke-PostgresAiTriage.ps1 `
  -Host prod-db.example.com `
  -Database production `
  -Username app_user `
  -ReportPath "C:\TriageReports" `
  -LogPath "C:\TriageLogs" `
  -HistoryPath "C:\TriageHistory"
```

## Output Format

### Full Report (JSON)
Generated in `Reports/Triage_YYYYMMDD_HHMMSS.json`

```json
{
  "Timestamp": "2026-05-17T10:30:45-05:00",
  "Host": "localhost",
  "Port": "5432",
  "Database": "mydb",
  "Detectors": [
    {
      "Detector": "01-TopSlowQueries.sql",
      "Status": "Success",
      "Result": {
        "detector_result": {
          "DetectorName": "TopSlowQueries",
          "IssueKey": "TOP_SLOW_20260517_1030",
          "SeverityScore": 7,
          "Summary": "Found 4 slow-running queries with mean execution time > 1 second",
          "DetailsJson": [...]
        }
      }
    }
  ]
}
```

### Summary Report
Generated in `History/Triage_Summary_YYYYMMDD_HHMMSS.txt`

Text summary with detector results and severity levels.

### Execution Log
Generated in `Logs/Triage_YYYYMMDD_HHMMSS.log`

Timestamped log of all operations for debugging and auditing.

## Detector Details

### 01-TopSlowQueries.sql
Identifies slow-running queries using `pg_stat_statements` extension.

**Output Fields:**
- `queryid`: Unique query identifier
- `query`: Query text
- `calls`: Number of times executed
- `mean_exec_time_ms`: Average execution time
- `max_exec_time_ms`: Maximum execution time
- `rows`: Rows returned
- `shared_blks_hit`: Shared buffer cache hits
- `shared_blks_read`: Shared buffer cache misses/reads
- `temp_blks_written`: Temporary block writes

**Severity Scoring:**
- 0 = No slow queries found
- 5 = 1-3 slow queries
- 7 = 4-5 slow queries
- 9 = 6+ slow queries

**Uses:**
- `pg_stat_statements`

### 02-Blocking.sql
Identifies active blocking scenarios using `pg_blocking_pids()` function to detect waiter/blocker relationships.

**Criteria:**
- Sessions that are blocked or blocking other sessions
- Requires PostgreSQL 13+ for `pg_blocking_pids()` function

**Output Fields:**
- `pid`: Process ID
- `user`: Database user
- `query`: Current query (truncated to 200 chars)
- `state`: Connection state
- `duration_seconds`: How long the session has been active
- `role`: Either 'blocked' or 'blocking'
- `blocked_by_pids`: Array of PIDs causing the block

**Severity Scoring:**
- 0 = No blocking detected
- 6 = 1 blocking scenario
- 8 = 2-5 blocking scenarios
- 10 = 6+ blocking scenarios

**Uses:**
- `pg_stat_activity`
- `pg_blocking_pids()` function

### 03-DeadTupleVacuumRisk.sql
Identifies tables with high dead tuple ratios and vacuum risk using `pg_stat_user_tables`.

**Note:** This detector identifies *dead tuple accumulation risk*, not true physical disk bloat. It looks at statistics from vacuum/autovacuum operations to flag tables needing maintenance.

**Criteria:**
- Tables with > 10% dead tuples
- Tables not vacuumed in > 7 days

**Risk Levels:**
- **CRITICAL**: > 30% dead tuples AND no vacuum for > 24 hours
- **HIGH**: > 20% dead tuples AND no vacuum for > 12 hours
- **MEDIUM**: > 10% dead tuples
- **LOW**: Below thresholds

**Severity Scoring:**
- 0 = No risk detected
- 6 = Medium risk stat_user_tables`
- `SELECT` on `pg_stat_statements` (if extension is enabled)

These are typically available to normal database users.

### Recommended (Best Full Coverage)
Grant the `pg_read_all_stats` role to your triage user:

```sql
GRANT pg_read_all_stats TO triage_user;
```

This role provides visibility into all session activity and statistics, which is necessary for:
- Blocking detection to see all active sessions
- Slow query analysis with complete statistics
- Table statistics for all user tables

### To Enable Full Functionality
```sql
-- Grant access if using restricted user
GRANT CONNECT ON DATABASE mydb TO app_user;
GRANT USAGE ON SCHEMA pg_catalog TO app_user;

-- For full statistics visibility (recommended)
GRANT pg_read_all_stats TO app_user;

-- For pg_stat_statements (optional, requires superuser to instal
Each detector returns a single JSON object with this structure:

```json
{
  "DetectorName": "string - Name of the detector",
  "IssueKey": "string - Unique identifier (format: PREFIX_YYYYMMDD_HHMM)",
  "SeverityScore": "0-10 - Severity level",
  "Summary": "string - Human-readable summary",
  "DetailsJson": "object or array - Detailed findings"
}
```

## Permissions Requirements
 if the extension is not installed. To enable:
```sql
-- As superuser
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
GRANT SELECT ON pg_stat_statements TO triage_user;
```

### PostgreSQL Version Too Old
The `pg_blocking_pids()` function requires PostgreSQL 13+. On older versions, the blocking detector will fail. Consider upgrading or disabling that detector by removing `02-Blocking.sql` from the Scripts directory.

### Permission Denied Errors
Verify user has required permissions:
```sql
-- As superuser, grant read all stats
GRANT pg_read_all_stats TO triage
```sql
-- Grant access if using restricted user
GRANT CONNECT ON DATABASE mydb TO app_user;
GRANT USAGE ON SCHEMA pg_catalog TO app_user;
pg_read_all_stats TO triage_user;

-- Optional: For slow query analysis
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
GRANT SELECT ON pg_stat_statements TO triage_user;
```

2. Store connection parameters in secure config file or use environment variables

3. Schedule regular execution using Windows Task Scheduler:
```powershell
# Create a scheduled task
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\path\to\Invoke-PostgresAiTriage.ps1 -Pg
# Windows
$env:Path += ";C:\Program Files\PostgreSQL\15\bin"

# Or set permanently in PowerShell profile
```

### Connection Refused
Verify connection parameters:
```powershell
# Test connection
psql -h localhost -p 5432 -U postgres -d mydb -c "SELECT version();"
```

### pg_stat_statements Extension Not Installed
This detector will skip gracefully. To enable:
```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

### Permission Denied Errors
Verify user has SELECT permissions on system catalogs:
```sql
-- As superuser
GRANT SELECT ON ALL TABLES IN SCHEMA pg_catalog TO app_user;
```

## Configuration for Production Use

1. Create dedicated triage database user with minimal permissions:
```sql
CREATE USER triage_user WITH PASSWORD 'secure_password';
GRANT CONNECT ON DATABASE production TO triage_user;
GRANT USAGE ON SCHEMA pg_catalog TO triage_user;
GRANT SELECT ON pg_stat_activity TO triage_user;
GRANT SELECT ON pg_locks TO triage_user;
GRANT SELECT ON pg_stat_user_tables TO triage_user;
```

2. Store connection parameters in secure config file or use environment variables

3. Schedule regular execution using Windows Task Scheduler:
```powershell
# Create a scheduled task
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\path\to\Invoke-PostgresAiTriage.ps1 -Host proddb -Database prod -Username triage_user -Port 5432'
$trigger = New-ScheduledTaskTrigger -Daily -At 2AM
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "PostgreSQL AI Triage"
```

## Future Enhancements

- [ ] Additional detectors (index usage, replication lag, etc.)
- [ ] Thresholds configuration file
- [ ] Email/webhook notifications for high-severity issues
- [ ] Historical trend analysis
- [ ] Multi-database support
- [ ] Custom detector plugin system

## License

MIT

## Contributing

Contributions welcome! Please submit pull requests or open issues.

## Support

For issues and feature requests, please open an issue on GitHub.
