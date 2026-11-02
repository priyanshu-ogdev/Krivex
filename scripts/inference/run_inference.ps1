# =============================================================================
# scripts/inference/run_inference.ps1
# Master launcher & orchestrator for the Krivex Inference subsystem (Windows native).
#
# Usage:
#   .\scripts\inference\run_inference.ps1                     # MockBackend, no GPU needed (port 8420)
#   .\scripts\inference\run_inference.ps1 -Real              # Real backends, GPU required
#   .\scripts\inference\run_inference.ps1 -Real -LowVram     # Real backends, CPU offload for <16GB VRAM
#   .\scripts\inference\run_inference.ps1 -WithFrontend      # Runs backend and launches Node.js frontend
#   .\scripts\inference\run_inference.ps1 -CliSession        # Runs interactive CLI agentic session
#   .\scripts\inference\run_inference.ps1 -Setup             # Installs dependencies for inference
# =============================================================================

[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$Real,
    [switch]$LowVram,
    [string]$BindHost = "127.0.0.1",
    [int]$Port = 8420,
    [switch]$WithFrontend,
    [switch]$CliSession,
    [switch]$Setup,
    [double]$RamEnvelopeGb = 0.0,
    [double]$VramEnvelopeGb = 0.0,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"

# Navigate to monorepo root (2 levels up from scripts/inference)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
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

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "     Krivex Inference -- Master Service Launcher (PowerShell)   " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

if ($Help) {
    Write-Host @"
Usage:
  .\scripts\inference\run_inference.ps1                     # MockBackend, no GPU needed (port 8420)
  .\scripts\inference\run_inference.ps1 -Real              # Real backends, GPU required
  .\scripts\inference\run_inference.ps1 -Real -LowVram     # Real backends, CPU offload for <=12GB VRAM & <=16GB RAM
  .\scripts\inference\run_inference.ps1 -WithFrontend      # Runs backend and launches Node.js frontend
  .\scripts\inference\run_inference.ps1 -CliSession        # Runs interactive CLI agentic session
  .\scripts\inference\run_inference.ps1 -Setup             # Installs dependencies for inference
  .\scripts\inference\run_inference.ps1 -Help              # Displays this help screen

Parameters:
  -Real               Use real models (GPU + models/ weights required)
  -LowVram            Offload models for <=12GB VRAM and <=16GB RAM peak hardware
  -BindHost <ip>      IP to bind service (default: 127.0.0.1)
  -Port <int>         Port to listen on (default: 8420)
  -WithFrontend       Concurrently starts the Node.js frontend on port 3100
  -CliSession         Launches the interactive CLI agentic design session
  -Setup              Installs Python virtualenv dependencies for inference
"@ -ForegroundColor Yellow
    exit 0
}

# 1. Handle Setup
if ($Setup) {
    Write-Host "[*] Launching Inference environment setup..." -ForegroundColor Cyan
    & powershell -File ".\scripts\inference\setup_env_inference.ps1"
    exit $LASTEXITCODE
}

# 2. Check and activate virtual environment
$VenvActivate = Join-Path $RepoRoot ".venv\Scripts\Activate.ps1"
if (Test-Path $VenvActivate) {
    & $VenvActivate
} else {
    Write-Host "[!] Note: Virtualenv .venv not found at repo root. Running against active Python environment." -ForegroundColor DarkGray
}

# 3. Handle CLI session mode
if ($CliSession) {
    Write-Host "[*] Starting Krivex Interactive CLI Agentic Session..." -ForegroundColor Cyan
    $env:PYTHONPATH = "inference\src;training\src;" + $env:PYTHONPATH
    & python -m krivex_inference.cli session @RemainingArgs
    exit $LASTEXITCODE
}

# 4. Configure Environment Variables for Service Launch
if ($Real) {
    $env:KRIVEX_USE_REAL_BACKENDS = "1"
    Write-Host "[*] Real backends mode ENABLED (GPU required)." -ForegroundColor Yellow
    if ($LowVram) {
        $env:KRIVEX_LOW_VRAM_MODE = "1"
        if ($VramEnvelopeGb -le 0.0) { $VramEnvelopeGb = 12.0 }
        if ($RamEnvelopeGb -le 0.0) { $RamEnvelopeGb = 16.0 }
        Write-Host "[*] Low-VRAM envelope (<=12GB VRAM, <=16GB RAM peak) offload ENABLED." -ForegroundColor Magenta
    } else {
        if ($VramEnvelopeGb -le 0.0) { $VramEnvelopeGb = 24.0 }
        if ($RamEnvelopeGb -le 0.0) { $RamEnvelopeGb = 32.0 }
    }
} else {
    $env:KRIVEX_USE_REAL_BACKENDS = "0"
    Write-Host "[*] MockBackend mode (CPU-friendly, no GPU required, test-only)." -ForegroundColor Green
}

if ($VramEnvelopeGb -gt 0.0) {
    $env:KRIVEX_VRAM_ENVELOPE_GB = [string]$VramEnvelopeGb
}
if ($RamEnvelopeGb -gt 0.0) {
    $env:KRIVEX_RAM_ENVELOPE_GB = [string]$RamEnvelopeGb
}

$env:KRIVEX_PORT = [string]$Port
$env:KRIVEX_BIND_HOST = $BindHost
$env:PYTHONPATH = "inference\src;training\src;" + $env:PYTHONPATH

# 5. Optionally launch Node.js Frontend concurrently
if ($WithFrontend) {
    Write-Host "[*] Starting Node.js frontend in background..." -ForegroundColor Cyan
    $frontendDir = Join-Path $RepoRoot "inference\frontend"
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$frontendDir'; npm start" -WindowStyle Normal
    Start-Sleep -Seconds 2
}

# 6. Resolve Python & Launch FastAPI Service with Dedicated Logging
$Python = ""
if ($env:PYTHON_EXECUTABLE -and (Test-Path $env:PYTHON_EXECUTABLE)) {
    $Python = $env:PYTHON_EXECUTABLE
} elseif (Test-Path (Join-Path $RepoRoot ".venv\Scripts\python.exe")) {
    $Python = Join-Path $RepoRoot ".venv\Scripts\python.exe"
} elseif (Test-Path (Join-Path $RepoRoot ".venv\python.exe")) {
    $Python = Join-Path $RepoRoot ".venv\python.exe"
} elseif ($env:CONDA_PREFIX -and (Test-Path (Join-Path $env:CONDA_PREFIX "python.exe"))) {
    $Python = Join-Path $env:CONDA_PREFIX "python.exe"
} else {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) { $Python = $cmd.Source } else { $Python = "python" }
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$InfLogDir = Join-Path $RepoRoot "logs\inference"
if (-not (Test-Path $InfLogDir)) { New-Item -ItemType Directory -Path $InfLogDir -Force | Out-Null }
$InfLogFile = Join-Path $InfLogDir "inference_$Timestamp.log"

Write-Host "[LOG] Capturing stdout and stderr to: $InfLogFile" -ForegroundColor DarkGray
Write-Host "[*] Starting Krivex Inference FastAPI Service on http://${BindHost}:${Port} ..." -ForegroundColor Green

& $Python -m krivex_inference.orchestrator.service --host $BindHost --port $Port @RemainingArgs 2>&1 | Tee-Object -FilePath $InfLogFile -Append
$code = $LASTEXITCODE
Copy-Item $InfLogFile (Join-Path $InfLogDir "latest.log") -Force -ErrorAction SilentlyContinue
Copy-Item $InfLogFile (Join-Path (Join-Path $RepoRoot "logs") "latest.log") -Force -ErrorAction SilentlyContinue
exit $code
