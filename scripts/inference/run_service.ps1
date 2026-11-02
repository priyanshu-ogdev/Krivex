# =============================================================================
# scripts/inference/run_service.ps1
# Runs the Krivex Inference FastAPI service on Windows native PowerShell.
#
# Usage:
#   .\scripts\inference\run_service.ps1
#   .\scripts\inference\run_service.ps1 -BindHost "0.0.0.0" -Port 8080
# =============================================================================

[CmdletBinding()]
param(
    [string]$BindHost = "127.0.0.1",
    [int]$Port = 8420,
    [switch]$NoReload,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot = Resolve-Path (Join-Path $ScriptDir "..\..")
Set-Location $RepoRoot

# 1. Auto-load .env into process environment if present
$EnvFile = Join-Path $RepoRoot ".env"
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $parts = $line.Split("=", 2)
            $name = $parts[0].Trim()
            $val = $parts[1].Trim().Trim("'", '"')
            if ($name -and -not [System.Environment]::GetEnvironmentVariable($name)) {
                [System.Environment]::SetEnvironmentVariable($name, $val, "Process")
            }
        }
    }
}

# Force UTF-8 on Windows Console
if ([Console]::OutputEncoding.CodePage -ne 65001) {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}

Write-Host "Starting Krivex Inference service on http://$($BindHost):$Port..." -ForegroundColor Cyan

if ($env:KRIVEX_USE_REAL_BACKENDS -eq "1") {
    Write-Host "KRIVEX_USE_REAL_BACKENDS=1 -- real model backends, GPU required." -ForegroundColor Yellow
    Write-Host "Planner tier uses frozen Qwen3.5-9B GGUF; Polish tier uses Qwen-Image-2.1." -ForegroundColor Yellow
    if ($env:KRIVEX_LOW_VRAM_MODE -eq "1") {
        Write-Host "KRIVEX_LOW_VRAM_MODE=1 -- targeting low-VRAM envelope (<=12GB VRAM, <=16GB RAM peak)." -ForegroundColor Magenta
    }
} else {
    Write-Host "MockBackend mode (default) -- no GPU/weights needed." -ForegroundColor DarkCyan
    Write-Host "Set `$env:KRIVEX_USE_REAL_BACKENDS='1' to use real model backends." -ForegroundColor DarkGray
}

# Resolve Python interpreter
$PythonBin = "python"
if ($env:PYTHON_EXECUTABLE -and (Test-Path $env:PYTHON_EXECUTABLE)) {
    $PythonBin = $env:PYTHON_EXECUTABLE
} elseif (Test-Path (Join-Path $RepoRoot ".venv\Scripts\python.exe")) {
    $PythonBin = Join-Path $RepoRoot ".venv\Scripts\python.exe"
} elseif (Test-Path (Join-Path $RepoRoot ".venv\python.exe")) {
    $PythonBin = Join-Path $RepoRoot ".venv\python.exe"
} elseif ($env:CONDA_PREFIX -and (Test-Path (Join-Path $env:CONDA_PREFIX "python.exe"))) {
    $PythonBin = Join-Path $env:CONDA_PREFIX "python.exe"
}

# Ensure PYTHONPATH
$InfSrc = Join-Path $RepoRoot "inference\src"
$TrainSrc = Join-Path $RepoRoot "training\src"
$env:PYTHONPATH = "$InfSrc;$TrainSrc;$env:PYTHONPATH"

$UvicornArgs = @(
    "-m", "uvicorn",
    "krivex_inference.orchestrator.service:app",
    "--host", $BindHost,
    "--port", [string]$Port
)

if (-not $NoReload) {
    $UvicornArgs += "--reload"
}

if ($RemainingArgs) {
    $UvicornArgs += $RemainingArgs
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$InfLogDir = Join-Path $RepoRoot "logs\inference"
if (-not (Test-Path $InfLogDir)) { New-Item -ItemType Directory -Path $InfLogDir -Force | Out-Null }
$SrvLogFile = Join-Path $InfLogDir "service_$Timestamp.log"

Write-Host "[LOG] Capturing stdout and stderr to: $SrvLogFile" -ForegroundColor DarkGray
& $PythonBin $UvicornArgs 2>&1 | Tee-Object -FilePath $SrvLogFile -Append
$code = $LASTEXITCODE
Copy-Item $SrvLogFile (Join-Path $InfLogDir "latest.log") -Force -ErrorAction SilentlyContinue
Copy-Item $SrvLogFile (Join-Path (Join-Path $RepoRoot "logs") "latest.log") -Force -ErrorAction SilentlyContinue
exit $code
