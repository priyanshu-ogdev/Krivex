# =============================================================================
# scripts/data-forge/setup_env.ps1
# Sets up Windows development environment for Krivex Data-Forge.
#
# Usage:
#   .\scripts\data-forge\setup_env.ps1
#   .\scripts\data-forge\setup_env.ps1 -UseConda
#   .\scripts\data-forge\setup_env.ps1 -CondaEnvName "krivex"
# =============================================================================

[CmdletBinding()]
param(
    [switch]$UseConda,
    [string]$CondaEnvName = "krivex",
    [switch]$Help
)

$ErrorActionPreference = "Stop"

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
Set-Location $RepoRoot

# Force UTF-8 on Windows Console
if ([Console]::OutputEncoding.CodePage -ne 65001) {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "   Krivex Data-Forge -- Windows Environment Setup               " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

Write-Host "NOTE: vLLM has no official native-Windows build." -ForegroundColor Yellow
Write-Host "Deterministic stages (manifests, TrueType wireframes, FAISS-CPU)" -ForegroundColor DarkGray
Write-Host "run 100% on Windows. For GPU VLM stages (DeepSeek-OCR, Qwen VLM)," -ForegroundColor DarkGray
Write-Host "run inside Windows 11 + WSL2 (Ubuntu) via ./scripts/data-forge/setup_env.sh" -ForegroundColor DarkGray
Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray

# 1. Resolve Python & Pip executable paths
$Python = ""
$Pip = ""

if ($UseConda -or ($env:CONDA_DEFAULT_ENV -and -not (Test-Path "$RepoRoot\.venv"))) {
    Write-Host "[1/4] Configuring Conda environment ($CondaEnvName)..." -ForegroundColor Cyan
    $condaCmd = Get-Command conda -ErrorAction SilentlyContinue
    if (-not $condaCmd) {
        Write-Host "ERROR: conda not found in PATH. Install Miniconda or run without -UseConda to use .venv." -ForegroundColor Red
        exit 1
    }

    $envList = conda env list
    if ($envList -notmatch "(?m)^$CondaEnvName\s") {
        Write-Host "Creating conda environment '$CondaEnvName' with Python 3.11..." -ForegroundColor DarkGray
        & conda create -n $CondaEnvName python=3.11 -y
    } else {
        Write-Host "Reusing existing conda environment '$CondaEnvName'." -ForegroundColor DarkGray
    }

    $condaBasePath = (conda info --base).Trim()
    $candidatePy = Join-Path $condaBasePath "envs\$CondaEnvName\python.exe"
    if (-not (Test-Path $candidatePy)) {
        $userEnvs = Join-Path $env:USERPROFILE ".conda\envs\$CondaEnvName\python.exe"
        if (Test-Path $userEnvs) { $candidatePy = $userEnvs }
    }

    if (Test-Path $candidatePy) {
        $Python = $candidatePy
        $Pip = Join-Path (Split-Path -Parent $candidatePy) "Scripts\pip.exe"
    } else {
        $Python = "python"
        $Pip = "pip"
    }
} else {
    Write-Host "[1/4] Configuring Python virtual environment (.venv)..." -ForegroundColor Cyan
    $VenvDir = Join-Path $RepoRoot ".venv"
    if (-not (Test-Path $VenvDir)) {
        Write-Host "Creating virtual environment at $VenvDir..." -ForegroundColor DarkGray
        python -m venv $VenvDir
    }
    $Python = Join-Path $VenvDir "Scripts\python.exe"
    $Pip = Join-Path $VenvDir "Scripts\pip.exe"
}

Write-Host "Using Python: $Python" -ForegroundColor DarkGray

# 2. Upgrade packaging tools
Write-Host "[2/4] Ensuring pip, setuptools, and wheel are up to date..." -ForegroundColor Cyan
& $Python -m pip install --upgrade pip setuptools wheel

# 3. Install sealed PyTorch 2.11 with CUDA 12 support
Write-Host "[3/4] Installing PyTorch 2.11 with CUDA 12.4 support & FAISS-CPU..." -ForegroundColor Cyan
& $Pip install "torch>=2.11.0,<2.12.0" "torchvision>=0.26.0,<0.27.0" --index-url https://download.pytorch.org/whl/cu124
& $Pip install faiss-cpu

# 4. Install Data-Forge in editable mode
Write-Host "[4/4] Installing data-forge package in editable mode..." -ForegroundColor Cyan
& $Pip install -e "$RepoRoot\data-forge[dev]"

Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "   Data-Forge Windows environment is ready!                     " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Audit data contracts:     .\scripts\data-forge\run_data_forge.ps1 audit" -ForegroundColor Yellow
Write-Host "  2. Run pipeline dry-run:     .\scripts\data-forge\run_data_forge.ps1 run --dry-run" -ForegroundColor Yellow
