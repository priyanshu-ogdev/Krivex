<#
.SYNOPSIS
    Native Windows Detached Background Process Manager (Windows equivalent of nohup & tmux).

.DESCRIPTION
    Runs any long-running command in a detached, persistent background process that survives
    SSH session disconnects, laptop lid closes, and network drops. Provides commands to start,
    monitor live logs, check process health, and gracefully terminate jobs.

.PARAMETER Start
    The command line or script to execute in the background.

.PARAMETER Log
    Path to write stdout and stderr (default: "job_<timestamp>.log" or "training.log").

.PARAMETER Status
    Displays active detached background jobs and process metrics (PID, CPU, Memory).

.PARAMETER Follow
    Live streams the output log file (like 'tail -f' or 'tmux attach'). Press Ctrl+C to detach without killing the job.

.PARAMETER Stop
    Terminates the active detached background process.

.EXAMPLE
    .\scripts\run_detached.ps1 -Start ".\scripts\training\train_all.ps1 -Tier polish-default" -Log "training.log"
    .\scripts\run_detached.ps1 -Status
    .\scripts\run_detached.ps1 -Follow
    .\scripts\run_detached.ps1 -Stop
#>

[CmdletBinding()]
param(
    [string]$Start = "",
    [string]$Log = "training.log",
    [switch]$Status,
    [switch]$Follow,
    [switch]$Stop,
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

$PidFile = Join-Path $RepoRoot ".detached_job.pid"
$LogFile = Join-Path $RepoRoot $Log

if ($Help -or (-not $Start -and -not $Status -and -not $Follow -and -not $Stop)) {
    Write-Host @"
================================================================
   Krivex Detached Process Manager (Windows nohup Equivalent)   
================================================================
Usage:
  .\scripts\run_detached.ps1 -Start "<command>" [-Log "<file>"]
  .\scripts\run_detached.ps1 -Status
  .\scripts\run_detached.ps1 -Follow [-Log "<file>"]
  .\scripts\run_detached.ps1 -Stop

Examples:
  # 1. Launch training in background (survives SSH disconnect):
  .\scripts\run_detached.ps1 -Start ".\scripts\training\train_all.ps1 -Tier polish-default"

  # 2. Check if job is alive:
  .\scripts\run_detached.ps1 -Status

  # 3. Stream live progress (Ctrl+C to detach without killing job):
  .\scripts\run_detached.ps1 -Follow

  # 4. Stop running job:
  .\scripts\run_detached.ps1 -Stop
"@ -ForegroundColor Yellow
    exit 0
}

# ------------------------------------------------------------------------------
# Action: Stop
# ------------------------------------------------------------------------------
if ($Stop) {
    if (-not (Test-Path $PidFile)) {
        Write-Host "[!] No active detached job found (missing .detached_job.pid)." -ForegroundColor Yellow
        exit 0
    }
    $jobPid = (Get-Content $PidFile -Raw).Trim()
    try {
        $proc = Get-Process -Id $jobPid -ErrorAction Stop
        Write-Host "[*] Terminating process $jobPid ($($proc.ProcessName))..." -ForegroundColor Yellow
        Stop-Process -Id $jobPid -Force -ErrorAction SilentlyContinue
        # Also kill any child python processes
        Get-Process python -ErrorAction SilentlyContinue | ForEach-Object {
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
        Write-Host "[SUCCESS] Job terminated." -ForegroundColor Green
    } catch {
        Write-Host "[!] Process $jobPid was not running. Cleaning PID file." -ForegroundColor DarkGray
        Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
    }
    exit 0
}

# ------------------------------------------------------------------------------
# Action: Status
# ------------------------------------------------------------------------------
if ($Status) {
    if (-not (Test-Path $PidFile)) {
        Write-Host "[i] No active detached job registered." -ForegroundColor DarkGray
        # Also check if any standalone python training jobs are running
        $pyProcs = Get-Process python -ErrorAction SilentlyContinue
        if ($pyProcs) {
            Write-Host "`nActive Python processes detected on host:" -ForegroundColor Cyan
            $pyProcs | Select-Object Id, ProcessName, CPU, @{Name="RAM (MB)"; Expression={[math]::Round($_.WorkingSet64 / 1MB, 1)}} | Format-Table -AutoSize
        }
        exit 0
    }
    $jobPid = (Get-Content $PidFile -Raw).Trim()
    try {
        $proc = Get-Process -Id $jobPid -ErrorAction Stop
        Write-Host "[*] Detached Job is ACTIVE (PID: $jobPid)" -ForegroundColor Green
        $proc | Select-Object Id, ProcessName, StartTime, CPU, @{Name="RAM (MB)"; Expression={[math]::Round($_.WorkingSet64 / 1MB, 1)}} | Format-Table -AutoSize
        
        $pyProcs = Get-Process python -ErrorAction SilentlyContinue
        if ($pyProcs) {
            Write-Host "Worker Python processes:" -ForegroundColor Cyan
            $pyProcs | Select-Object Id, ProcessName, CPU, @{Name="RAM (MB)"; Expression={[math]::Round($_.WorkingSet64 / 1MB, 1)}} | Format-Table -AutoSize
        }
        if (Test-Path $LogFile) {
            Write-Host "Latest 5 lines from log ($LogFile):" -ForegroundColor DarkGray
            Get-Content $LogFile -Tail 5 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        }
    } catch {
        Write-Host "[!] Job process $jobPid is no longer running." -ForegroundColor Yellow
        Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
    }
    exit 0
}

# ------------------------------------------------------------------------------
# Action: Follow
# ------------------------------------------------------------------------------
if ($Follow) {
    if (-not (Test-Path $LogFile)) {
        Write-Host "[ERROR] Log file not found at: $LogFile" -ForegroundColor Red
        exit 1
    }
    Write-Host "[*] Streaming live log: $LogFile" -ForegroundColor Cyan
    Write-Host "[i] Press Ctrl+C to detach at any time. (Job will keep running in background!)" -ForegroundColor DarkGray
    Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
    Get-Content -Path $LogFile -Wait -Tail 20
    exit 0
}

# ------------------------------------------------------------------------------
# Action: Start
# ------------------------------------------------------------------------------
if ($Start) {
    # Check if a job is already registered
    if (Test-Path $PidFile) {
        $oldPid = (Get-Content $PidFile -Raw).Trim()
        $existing = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Host "[ERROR] A detached job is already running with PID $oldPid." -ForegroundColor Red
            Write-Host "Run '.\scripts\run_detached.ps1 -Stop' to terminate it first." -ForegroundColor Yellow
            exit 1
        }
    }

    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "   Launching Detached Process on Windows                        " -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "Command: $Start" -ForegroundColor Yellow
    Write-Host "Log:     $LogFile" -ForegroundColor Yellow

    # Initialize log file
    $logDir = Split-Path -Parent $LogFile
    if ($logDir -and -not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    "=== Krivex Detached Job Started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File -FilePath $LogFile -Encoding utf8

    # Build wrapped PowerShell execution line
    $wrappedCmd = "& { Set-Location '$RepoRoot'; $Start } *> '$LogFile'"
    $psArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-Command", $wrappedCmd
    )

    # Launch detached Win32 process independent of SSH console session
    $proc = Start-Process -FilePath "powershell.exe" -ArgumentList $psArgs -WindowStyle Hidden -PassThru

    # Save PID
    $proc.Id | Out-File -FilePath $PidFile -Encoding utf8

    Write-Host "`n[SUCCESS] Process spawned with PID: $($proc.Id)" -ForegroundColor Green
    Write-Host "The process is detached from your SSH session. You can safely disconnect!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Useful commands:" -ForegroundColor Cyan
    Write-Host "  Stream live output:   .\scripts\run_detached.ps1 -Follow" -ForegroundColor Yellow
    Write-Host "  Check job health:     .\scripts\run_detached.ps1 -Status" -ForegroundColor Yellow
    Write-Host "  Terminate job:        .\scripts\run_detached.ps1 -Stop" -ForegroundColor Yellow
    exit 0
}
