# PostgreSQL AI Triage Invocation Script
# Runs all detector scripts against a PostgreSQL database
# Collects results in JSON format and generates reports

param(
    [Parameter(Mandatory=$true)]
    [string]$Host,
    
    [Parameter(Mandatory=$true)]
    [string]$Database,
    
    [Parameter(Mandatory=$true)]
    [string]$Username,
    
    [Parameter(Mandatory=$false)]
    [string]$Port = "5432",
    
    [Parameter(Mandatory=$false)]
    [string]$Password,
    
    [Parameter(Mandatory=$false)]
    [string]$ReportPath = "$PSScriptRoot\..\Reports",
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$PSScriptRoot\..\Logs",
    
    [Parameter(Mandatory=$false)]
    [string]$HistoryPath = "$PSScriptRoot\..\History"
)

# Setup paths
$ScriptDir = Split-Path -Path $PSScriptRoot -Parent
$SqlDir = Join-Path $ScriptDir "Sql"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ReportFile = Join-Path $ReportPath "Triage_$Timestamp.json"
$LogFile = Join-Path $LogPath "Triage_$Timestamp.log"
$HistoryFile = Join-Path $HistoryPath "Triage_Summary_$Timestamp.txt"

# Create directories if they don't exist
@($ReportPath, $LogPath, $HistoryPath) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
    }
}

# Logging function
function Write-Log {
    param([string]$Message)
    $LogMessage = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Write-Host $LogMessage
    Add-Content -Path $LogFile -Value $LogMessage
}

# Initialize report
Write-Log "Starting PostgreSQL AI Triage..."
Write-Log "Target: $Host`:$Port/$Database"
$results = @{
    Timestamp = Get-Date -o o
    Host = $Host
    Port = $Port
    Database = $Database
    Detectors = @()
}

# Build psql connection string
$env:PGPASSWORD = if ($Password) { $Password } else { "" }
$psqlArgs = @(
    "-h", $Host,
    "-p", $Port,
    "-U", $Username,
    "-d", $Database,
    "-t",           # Tuples only
    "-q",           # Quiet
    "-X"            # No .psqlrc
)

# Execute each detector
$detectorFiles = @(
    "01-TopSlowQueries.sql",
    "02-Blocking.sql",
    "03-TableBloatVacuumRisk.sql"
)

foreach ($detector in $detectorFiles) {
    $sqlFile = Join-Path $SqlDir $detector
    
    if (-not (Test-Path $sqlFile)) {
        Write-Log "WARNING: Detector file not found: $sqlFile"
        continue
    }
    
    try {
        Write-Log "Running detector: $detector"
        
        $output = & psql @psqlArgs -f $sqlFile 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "ERROR: Detector $detector failed with exit code $LASTEXITCODE"
            Write-Log "Output: $output"
            continue
        }
        
        # Parse JSON result
        if ($output) {
            $detectorResult = $output | ConvertFrom-Json
            $results.Detectors += @{
                Detector = $detector
                Result = $detectorResult
                Status = "Success"
            }
            Write-Log "Detector $detector completed. IssueKey: $($detectorResult.IssueKey), Severity: $($detectorResult.SeverityScore)"
        }
    }
    catch {
        Write-Log "ERROR: Exception in detector $detector : $_"
        $results.Detectors += @{
            Detector = $detector
            Status = "Failed"
            Error = $_.Exception.Message
        }
    }
}

# Save full report
Write-Log "Saving report to: $ReportFile"
$results | ConvertTo-Json -Depth 10 | Out-File -FilePath $ReportFile -Encoding UTF8

# Create summary
$summary = @"
PostgreSQL AI Triage Report
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Target: $Host`:$Port/$Database

Detectors Run: $($results.Detectors.Count)
Successful: $($results.Detectors | Where-Object { $_.Status -eq 'Success' } | Measure-Object).Count
Failed: $($results.Detectors | Where-Object { $_.Status -eq 'Failed' } | Measure-Object).Count

Issues Found:
"@

foreach ($detectorResult in $results.Detectors | Where-Object { $_.Status -eq 'Success' }) {
    $issueInfo = $detectorResult.Result.detector_result
    $summary += "`r`n- $($issueInfo.DetectorName): Severity $($issueInfo.SeverityScore) - $($issueInfo.Summary)"
}

Write-Log "Saving summary to: $HistoryFile"
$summary | Out-File -FilePath $HistoryFile -Encoding UTF8

Write-Log "PostgreSQL AI Triage completed. Results saved to:"
Write-Log "  Full Report: $ReportFile"
Write-Log "  Summary: $HistoryFile"
Write-Log "  Log: $LogFile"

# Clear sensitive data
Remove-Item -Path env:PGPASSWORD -ErrorAction SilentlyContinue

exit $LASTEXITCODE
