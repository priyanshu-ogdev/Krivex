# =============================================================================
# scripts/inference/setup_env_inference.ps1
# Sets up virtual environment and installs dependencies for Krivex Inference.
#
# Usage:
#   .\scripts\inference\setup_env_inference.ps1
#   .\scripts\inference\setup_env_inference.ps1 -InstallBackends
# =============================================================================

[CmdletBinding()]
param(
    [switch]$InstallBackends,
    [switch]$RequireGPU
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot = Resolve-Path (Join-Path $ScriptDir "..\..")
Set-Location $RepoRoot

# Auto-load .env into process environment if present
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

# Dedicated Logging Setup
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogDir = Join-Path $RepoRoot "logs\inference"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = Join-Path $LogDir "setup_inference_$Timestamp.log"
Start-Transcript -Path $LogFile -Append | Out-Null
Write-Host "[LOG] Full stdout & stderr captured to: $LogFile" -ForegroundColor DarkGray

# Force UTF-8 on Windows Console
if ([Console]::OutputEncoding.CodePage -ne 65001) {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "       Krivex Inference -- Environment Setup (PowerShell)       " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 1. Resolve or create virtualenv
$VenvDir = Join-Path $RepoRoot ".venv"
$PythonBin = "python"
if (-not (Test-Path $VenvDir)) {
    Write-Host "[+] Creating virtual environment in .venv..." -ForegroundColor Green
    python -m venv $VenvDir
}
$VenvPython = Join-Path $VenvDir "Scripts\python.exe"
if (Test-Path $VenvPython) {
    $PythonBin = $VenvPython
}

Write-Host "[i] Using Python: $PythonBin" -ForegroundColor DarkGray

# 2. Upgrade pip and build tools
Write-Host "[+] Ensuring pip, setuptools, and wheel are up to date..." -ForegroundColor Green
& $PythonBin -m pip install --upgrade pip setuptools wheel

# 3. Install packages in editable mode
Write-Host "[+] Installing krivex-inference and krivex-training in editable mode..." -ForegroundColor Green
& $PythonBin -m pip install -e "$RepoRoot\inference"
& $PythonBin -m pip install -e "$RepoRoot\training"

# 4. Hardware compatibility check
Write-Host "[+] Running hardware preflight verification..." -ForegroundColor Green
$checkArgs = @("$RepoRoot\scripts\inference\check_hardware.py")
if ($RequireGPU) {
    $checkArgs += "--require-gpu"
}
& $PythonBin @checkArgs
if ($LASTEXITCODE -ne 0 -and $RequireGPU) {
    Write-Host "[ERROR] GPU check failed and -RequireGPU was specified. Halting." -ForegroundColor Red
    exit 1
}

# 5. Install backend dependencies if requested
if ($InstallBackends) {
    Write-Host "[+] Installing real model backend dependencies (torch, diffusers, transformers, bitsandbytes)..." -ForegroundColor Yellow
    & $PythonBin -m pip install "torch>=2.11.0,<2.12.0" "torchvision>=0.26.0,<0.27.0" --index-url https://download.pytorch.org/whl/cu126
    & $PythonBin -m pip install -e "$RepoRoot\inference[backends]"
} else {
    Write-Host "[i] Core dev dependencies installed. Pass -InstallBackends to install full GPU/Torch stack." -ForegroundColor DarkGray
}

Write-Host "================================================================" -ForegroundColor Green
Write-Host "   Inference environment setup complete!                        " -ForegroundColor Green
try {
    Stop-Transcript | Out-Null
    Copy-Item $LogFile (Join-Path $LogDir "latest.log") -Force -ErrorAction SilentlyContinue
    Copy-Item $LogFile (Join-Path (Join-Path $RepoRoot "logs") "latest.log") -Force -ErrorAction SilentlyContinue
} catch {}
Write-Host "================================================================" -ForegroundColor Green
