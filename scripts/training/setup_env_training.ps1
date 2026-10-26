<#
.SYNOPSIS
    Set up Python virtual environment and dependencies for Krivex Model Training on Windows.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
Set-Location $RepoRoot

# Force UTF-8 on Windows Console
if ([Console]::OutputEncoding.CodePage -ne 65001) {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}

Write-Host "Setting up Krivex training environment on Windows..." -ForegroundColor Cyan

if (-not (Test-Path "$RepoRoot\.venv")) {
    Write-Host "Creating Python virtual environment in .venv..." -ForegroundColor DarkGray
    python -m venv "$RepoRoot\.venv"
}

$Python = "$RepoRoot\.venv\Scripts\python.exe"
$Pip = "$RepoRoot\.venv\Scripts\pip.exe"

Write-Host "Upgrading pip, setuptools, wheel..." -ForegroundColor DarkGray
& $Python -m pip install --upgrade pip setuptools wheel

Write-Host "Installing PyTorch 2.11 with CUDA 12 support..." -ForegroundColor DarkGray
& $Pip install "torch>=2.11.0,<2.12.0" "torchvision>=0.26.0,<0.27.0" --index-url https://download.pytorch.org/whl/cu124

Write-Host "Installing pinned training acceleration dependencies..." -ForegroundColor DarkGray
& $Pip install "accelerate==1.10.1" "peft==0.17.1" "datasets==4.2.1" "pyarrow==21.0.0"

Write-Host "Installing monorepo packages in editable mode..." -ForegroundColor DarkGray
& $Pip install -e "$RepoRoot\training[dev,polish]"
& $Pip install -e "$RepoRoot\data-forge[dev]"
& $Pip install -e "$RepoRoot\inference[dev]"

Write-Host "`n[SUCCESS] Training environment ready." -ForegroundColor Green
Write-Host "To activate in PowerShell:" -ForegroundColor Yellow
Write-Host "    .\.venv\Scripts\Activate.ps1" -ForegroundColor Yellow
