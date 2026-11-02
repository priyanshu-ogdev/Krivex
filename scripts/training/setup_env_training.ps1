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
$LogDir = Join-Path $RepoRoot "logs\training"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = Join-Path $LogDir "setup_training_$Timestamp.log"
Start-Transcript -Path $LogFile -Append | Out-Null
Write-Host "[LOG] Full stdout & stderr captured to: $LogFile" -ForegroundColor DarkGray

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
& $Pip install "torch>=2.11.0,<2.12.0" "torchvision>=0.26.0,<0.27.0" --index-url https://download.pytorch.org/whl/cu126

Write-Host "Installing pinned training acceleration dependencies..." -ForegroundColor DarkGray
& $Pip install "accelerate==1.10.1" "peft==0.17.1" "datasets>=3.0.0" "pyarrow==21.0.0"

Write-Host "Installing monorepo packages in editable mode..." -ForegroundColor DarkGray
& $Pip install -e "$RepoRoot\training[dev,polish]"
& $Pip install -e "$RepoRoot\data-forge[dev]"
& $Pip install -e "$RepoRoot\inference[dev]"

Write-Host "`n[SUCCESS] Training environment ready." -ForegroundColor Green
Write-Host "To activate in PowerShell:" -ForegroundColor Yellow
Write-Host "    .\.venv\Scripts\Activate.ps1" -ForegroundColor Yellow
try {
    Stop-Transcript | Out-Null
    Copy-Item $LogFile (Join-Path $LogDir "latest.log") -Force -ErrorAction SilentlyContinue
    Copy-Item $LogFile (Join-Path (Join-Path $RepoRoot "logs") "latest.log") -Force -ErrorAction SilentlyContinue
} catch {}
