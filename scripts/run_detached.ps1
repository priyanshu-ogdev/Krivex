<#
.SYNOPSIS
    Native Windows Detached Background Process Manager (Immortal Process Runner).

.DESCRIPTION
    Runs long-running training, data-forge, or inference jobs in a persistent, detached background
    process that survives SSH disconnects, laptop lid closes, and network drops.
    Automatically captures ALL streams (stdout, stderr, warnings, stack traces) into timestamped
    log files under logs/ and maintains symlinks to latest.log.

.PARAMETER Start
    The command line or script to execute in the background.

.PARAMETER Log
    Custom log path. If omitted, automatically writes to logs/detached/job_<timestamp>.log.

.PARAMETER Status
    Displays active detached job metrics (PID, CPU, RAM, active log, worker python processes).

.PARAMETER Follow
    Live streams the output log file (like 'tail -f' or 'tmux attach'). Press Ctrl+C to detach without killing the job.

.PARAMETER Stop
    Terminates the active detached background process and child Python workers.

.PARAMETER ListLogs
    Lists all historical log files across logs/ sorted by timestamp.

.EXAMPLE
    .\scripts\run_detached.ps1 -Start ".\scripts\training\train_all.ps1 -Tier polish-default"
    .\scripts\run_detached.ps1 -Status
    .\scripts\run_detached.ps1 -Follow
    .\scripts\run_detached.ps1 -ListLogs
    .\scripts\run_detached.ps1 -Stop
#>

[CmdletBinding()]
param(
    [string]$Start = "",
    [string]$Log = "",
    [switch]$Status,
    [switch]$Follow,
    [switch]$Stop,
    [switch]$ListLogs,
    [switch]$Help
)

$ErrorActionPreference = "Stop"
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
Set-Location $RepoRoot

# Force UTF-8 on Windows Console
if ([Console]::OutputEncoding.CodePage -ne 65001) {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}

$MetaFile = Join-Path $RepoRoot ".detached_job.json"
$LegacyPidFile = Join-Path $RepoRoot ".detached_job.pid"
$LogsBaseDir = Join-Path $RepoRoot "logs"
$DetachedLogsDir = Join-Path $LogsBaseDir "detached"

# Ensure log directories exist
if (-not (Test-Path $DetachedLogsDir)) {
    New-Item -ItemType Directory -Path $DetachedLogsDir -Force | Out-Null
}

if ($Help -or (-not $Start -and -not $Status -and -not $Follow -and -not $Stop -and -not $ListLogs)) {
    Write-Host @"
================================================================
   Krivex Immortal Process Runner (Windows nohup Equivalent)    
================================================================
Usage:
  .\scripts\run_detached.ps1 -Start "<command>" [-Log "<file>"]
  .\scripts\run_detached.ps1 -Status
  .\scripts\run_detached.ps1 -Follow
  .\scripts\run_detached.ps1 -ListLogs
  .\scripts\run_detached.ps1 -Stop

Examples:
  # 1. Launch training in background (survives SSH disconnect):
  .\scripts\run_detached.ps1 -Start ".\scripts\training\train_all.ps1 -Tier polish-default"

  # 2. Check if job is alive, see CPU/RAM, and view recent log lines:
  .\scripts\run_detached.ps1 -Status

  # 3. Stream live progress and stderr in real time (Ctrl+C to safely detach):
  .\scripts\run_detached.ps1 -Follow

  # 4. View all historical logs:
  .\scripts\run_detached.ps1 -ListLogs

  # 5. Stop running job:
  .\scripts\run_detached.ps1 -Stop
"@ -ForegroundColor Yellow
    exit 0
}

# ------------------------------------------------------------------------------
# Action: ListLogs
# ------------------------------------------------------------------------------
if ($ListLogs) {
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "   Krivex Execution Logs (logs/)                                " -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    if (-not (Test-Path $LogsBaseDir)) {
        Write-Host "No logs directory found." -ForegroundColor DarkGray
        exit 0
    }
    $logFiles = Get-ChildItem -Path $LogsBaseDir -Recurse -File -Filter "*.log" | Sort-Object LastWriteTime -Descending
    if (-not $logFiles) {
        Write-Host "No log files found in $LogsBaseDir." -ForegroundColor DarkGray
        exit 0
    }
    $logFiles | Select-Object @{Name="Relative Path"; Expression={$_.FullName.Replace($RepoRoot + "\", "")}}, @{Name="Size (KB)"; Expression={[math]::Round($_.Length / 1KB, 1)}}, LastWriteTime | Format-Table -AutoSize
    exit 0
}

# ------------------------------------------------------------------------------
# Action: Stop
# ------------------------------------------------------------------------------
if ($Stop) {
    $targetPid = $null
    $targetLog = $null
    if (Test-Path $MetaFile) {
        try {
            $meta = Get-Content $MetaFile -Raw | ConvertFrom-Json
            $targetPid = $meta.pid
            $targetLog = $meta.log_file
        } catch {}
    } elseif (Test-Path $LegacyPidFile) {
        $targetPid = (Get-Content $LegacyPidFile -Raw).Trim()
    }

    if (-not $targetPid) {
        Write-Host "[!] No active detached job registered." -ForegroundColor Yellow
        exit 0
    }

    try {
        $proc = Get-Process -Id $targetPid -ErrorAction Stop
        Write-Host "[*] Terminating process $targetPid ($($proc.ProcessName))..." -ForegroundColor Yellow
        Stop-Process -Id $targetPid -Force -ErrorAction SilentlyContinue
        # Gracefully stop child Python processes
        Get-Process python -ErrorAction SilentlyContinue | ForEach-Object {
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
        if ($targetLog -and (Test-Path $targetLog)) {
            "`n=== Krivex Detached Job Terminated Manually $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File -FilePath $targetLog -Append -Encoding utf8
        }
        Write-Host "[SUCCESS] Job terminated." -ForegroundColor Green
    } catch {
        Write-Host "[!] Process $targetPid was no longer running." -ForegroundColor DarkGray
    } finally {
        Remove-Item $MetaFile -Force -ErrorAction SilentlyContinue
        Remove-Item $LegacyPidFile -Force -ErrorAction SilentlyContinue
    }
    exit 0
}

# ------------------------------------------------------------------------------
# Action: Status
# ------------------------------------------------------------------------------
if ($Status) {
    if (-not (Test-Path $MetaFile)) {
        Write-Host "[i] No active detached job registered in .detached_job.json." -ForegroundColor DarkGray
        $pyProcs = Get-Process python -ErrorAction SilentlyContinue
        if ($pyProcs) {
            Write-Host "`nActive standalone Python processes detected on host:" -ForegroundColor Cyan
            $pyProcs | Select-Object Id, ProcessName, CPU, @{Name="RAM (MB)"; Expression={[math]::Round($_.WorkingSet64 / 1MB, 1)}} | Format-Table -AutoSize
        }
        exit 0
    }

    $meta = Get-Content $MetaFile -Raw | ConvertFrom-Json
    $targetPid = $meta.pid
    $targetLog = $meta.log_file
    $targetCmd = $meta.command
    $startTime = $meta.start_time

    try {
        $proc = Get-Process -Id $targetPid -ErrorAction Stop
        Write-Host "================================================================" -ForegroundColor Green
        Write-Host "   Detached Job ACTIVE (PID: $targetPid)                        " -ForegroundColor Green
        Write-Host "================================================================" -ForegroundColor Green
        Write-Host "Command   : $targetCmd" -ForegroundColor Cyan
        Write-Host "Started   : $startTime" -ForegroundColor DarkGray
        Write-Host "Log Path  : $targetLog" -ForegroundColor Yellow

        $proc | Select-Object Id, ProcessName, StartTime, CPU, @{Name="RAM (MB)"; Expression={[math]::Round($_.WorkingSet64 / 1MB, 1)}} | Format-Table -AutoSize

        $pyProcs = Get-Process python -ErrorAction SilentlyContinue
        if ($pyProcs) {
            Write-Host "Active Worker Python Processes:" -ForegroundColor Cyan
            $pyProcs | Select-Object Id, ProcessName, CPU, @{Name="RAM (MB)"; Expression={[math]::Round($_.WorkingSet64 / 1MB, 1)}} | Format-Table -AutoSize
        }

        if ($targetLog -and (Test-Path $targetLog)) {
            Write-Host "`n--- Tail of Log ($targetLog) ---" -ForegroundColor DarkGray
            Get-Content -Path $targetLog -Tail 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        }
    } catch {
        Write-Host "[!] Job process $targetPid has completed or stopped." -ForegroundColor Yellow
        if ($targetLog -and (Test-Path $targetLog)) {
            Write-Host "Latest output from ${targetLog}:" -ForegroundColor DarkGray
            Get-Content -Path $targetLog -Tail 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        }
        Remove-Item $MetaFile -Force -ErrorAction SilentlyContinue
        Remove-Item $LegacyPidFile -Force -ErrorAction SilentlyContinue
    }
    exit 0
}

# ------------------------------------------------------------------------------
# Action: Follow
# ------------------------------------------------------------------------------
if ($Follow) {
    $targetLog = $null
    if ($Log) {
        $targetLog = if ([System.IO.Path]::IsPathRooted($Log)) { $Log } else { Join-Path $RepoRoot $Log }
    } elseif (Test-Path $MetaFile) {
        try {
            $meta = Get-Content $MetaFile -Raw | ConvertFrom-Json
            $targetLog = $meta.log_file
        } catch {}
    } elseif (Test-Path (Join-Path $LogsBaseDir "latest.log")) {
        $targetLog = Join-Path $LogsBaseDir "latest.log"
    }

    if (-not $targetLog -or -not (Test-Path $targetLog)) {
        Write-Host "[ERROR] No active or latest log file found." -ForegroundColor Red
        Write-Host "Use '.\scripts\run_detached.ps1 -ListLogs' to inspect available logs." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "   Streaming Live Log: $targetLog" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "[i] Press Ctrl+C anytime to detach. (Job will keep running safely in background!)" -ForegroundColor DarkGray
    Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
    Get-Content -Path $targetLog -Wait -Tail 30
    exit 0
}

# ------------------------------------------------------------------------------
# Action: Start
# ------------------------------------------------------------------------------
if ($Start) {
    if (Test-Path $MetaFile) {
        try {
            $oldMeta = Get-Content $MetaFile -Raw | ConvertFrom-Json
            $existing = Get-Process -Id $oldMeta.pid -ErrorAction SilentlyContinue
            if ($existing) {
                Write-Host "[ERROR] A detached job is already active with PID $($oldMeta.pid)." -ForegroundColor Red
                Write-Host "Command: $($oldMeta.command)" -ForegroundColor Yellow
                Write-Host "Run '.\scripts\run_detached.ps1 -Stop' to terminate it first." -ForegroundColor Yellow
                exit 1
            }
        } catch {}
    }

    # Determine dedicated log file
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $targetLog = ""
    if ($Log) {
        $targetLog = if ([System.IO.Path]::IsPathRooted($Log)) { $Log } else { Join-Path $RepoRoot $Log }
    } else {
        $targetLog = Join-Path $DetachedLogsDir "job_$timestamp.log"
    }

    # Ensure log directory exists
    $logParent = Split-Path -Parent $targetLog
    if ($logParent -and -not (Test-Path $logParent)) {
        New-Item -ItemType Directory -Path $logParent -Force | Out-Null
    }

    # Initialize log with descriptive header
    $header = @"
================================================================================
KRIVEX IMMORTAL DETACHED RUN
Started At : $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Command    : $Start
Log File   : $targetLog
Streams    : All Streams Captured (1=stdout, 2=stderr, 3=warning, 4-6=debug)
================================================================================
"@
    $header | Out-File -FilePath $targetLog -Encoding utf8

    # Wrap command in PowerShell block capturing ALL STREAMS (*>)
    $wrappedCmd = "& { Set-Location '$RepoRoot'; $Start } *> '$targetLog'"
    $psArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-Command", $wrappedCmd
    )

    # Spawn fully detached Win32 process decoupled from SSH console
    $proc = Start-Process -FilePath "powershell.exe" -ArgumentList $psArgs -WindowStyle Hidden -PassThru

    # Save job metadata JSON
    $metaObj = [PSCustomObject]@{
        pid = $proc.Id
        command = $Start
        start_time = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        log_file = $targetLog
    }
    $metaObj | ConvertTo-Json | Out-File -FilePath $MetaFile -Encoding utf8
    $proc.Id | Out-File -FilePath $LegacyPidFile -Encoding utf8

    # Update latest.log pointers
    try {
        Copy-Item -Path $targetLog -Destination (Join-Path $DetachedLogsDir "latest.log") -Force -ErrorAction SilentlyContinue
        Copy-Item -Path $targetLog -Destination (Join-Path $LogsBaseDir "latest.log") -Force -ErrorAction SilentlyContinue
    } catch {}

    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "   IMMORTAL JOB SPAWNED (PID: $($proc.Id))                      " -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "Command   : $Start" -ForegroundColor Cyan
    Write-Host "Log File  : $targetLog" -ForegroundColor Yellow
    Write-Host "Streams   : All (stdout, stderr, warnings, exceptions) -> Dedicated Log" -ForegroundColor DarkGray
    Write-Host "`n[SAFE TO DISCONNECT] Process is detached. You can exit SSH or close your laptop!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Operational Commands:" -ForegroundColor Cyan
    Write-Host "  Follow live output :  .\scripts\run_detached.ps1 -Follow" -ForegroundColor Yellow
    Write-Host "  Check process status: .\scripts\run_detached.ps1 -Status" -ForegroundColor Yellow
    Write-Host "  List historical logs: .\scripts\run_detached.ps1 -ListLogs" -ForegroundColor Yellow
    Write-Host "  Stop job            : .\scripts\run_detached.ps1 -Stop" -ForegroundColor Yellow
    exit 0
}
