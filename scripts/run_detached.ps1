<#
.SYNOPSIS
    Native Windows Detached Background Process Manager (Immortal Process Runner).

.DESCRIPTION
    Runs long-running training, data-forge, or inference jobs in a persistent, detached background
    process that breaks away from OpenSSH Job Objects and survives SSH disconnects, laptop lid closes,
    and network drops. Automatically captures ALL streams (stdout, stderr, warnings, stack traces)
    into timestamped log files under logs/ and maintains symlinks/copies to latest.log.

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

$ErrorActionPreference = "Continue"
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
Set-Location $RepoRoot

# Force UTF-8 on Windows Console
if ([Console]::OutputEncoding.CodePage -ne 65001) {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}

# 1. Load .env if present
$EnvFile = Join-Path $RepoRoot ".env"
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $parts = $line.Split("=", 2)
            $name = $parts[0].Trim()
            $val = $parts[1].Trim().Trim("'", '"')
            if ($name) {
                [System.Environment]::SetEnvironmentVariable($name, $val, "Process")
            }
        }
    }
}

# 2. Resolve Python interpreter
$Python = ""
if ($env:PYTHON_EXECUTABLE -and (Test-Path $env:PYTHON_EXECUTABLE)) {
    $Python = $env:PYTHON_EXECUTABLE
} elseif (Test-Path (Join-Path $RepoRoot ".venv\Scripts\python.exe")) {
    $Python = Join-Path $RepoRoot ".venv\Scripts\python.exe"
} elseif (Test-Path (Join-Path $RepoRoot ".venv\python.exe")) {
    $Python = Join-Path $RepoRoot ".venv\python.exe"
} elseif (Test-Path (Join-Path $RepoRoot ".venv-forge\Scripts\python.exe")) {
    $Python = Join-Path $RepoRoot ".venv-forge\Scripts\python.exe"
} elseif ($env:CONDA_PREFIX -and (Test-Path (Join-Path $env:CONDA_PREFIX "python.exe"))) {
    $Python = Join-Path $env:CONDA_PREFIX "python.exe"
} else {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) {
        $Python = $cmd.Source
    } else {
        $Python = "python"
    }
}

$PyScript = Join-Path $ScriptDir "run_detached.py"

if ($Help -or (-not $Start -and -not $Status -and -not $Follow -and -not $Stop -and -not $ListLogs)) {
    & $Python $PyScript --help
    exit 0
}

if ($ListLogs) {
    & $Python $PyScript --list-logs
    exit $LASTEXITCODE
}

if ($Stop) {
    & $Python $PyScript --stop
    exit $LASTEXITCODE
}

if ($Status) {
    & $Python $PyScript --status
    exit $LASTEXITCODE
}

if ($Follow) {
    $argsList = @("--follow")
    if ($Log) { $argsList += @("--log", $Log) }
    & $Python $PyScript @argsList
    exit $LASTEXITCODE
}

if ($Start) {
    $argsList = @("--start", $Start)
    if ($Log) { $argsList += @("--log", $Log) }
    & $Python $PyScript @argsList
    exit $LASTEXITCODE
}
