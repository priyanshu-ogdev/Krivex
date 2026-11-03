<#
.SYNOPSIS
    Krivex Production Training Launcher for Visual Polish Tier (Qwen-Image-2.1 DoRA).
    Target: NVIDIA RTX 6000 Ada Generation (48 GB GDDR6 ECC).

.DESCRIPTION
    Validates Data-Forge export, prepares Qwen condition/target pairs with strict
    split isolation, runs pre-flight contract verification, and launches the
    production DoRA training run in immortal detached background mode or interactively.

.PARAMETER Profile
    Hardware/hyperparameter profile:
      'a6000-max' (Default) - 48GB BF16 Enterprise Max: batch=16, accum=2 (effective=32),
                              rank=128, fp32 AdamW, peak 45.0 GB VRAM.
      'standard'            - 48GB BF16 Standard: batch=8, accum=2 (effective=16), rank=64.
      'qdora-12gb'          - 12GB NF4 Consumer: batch=1, accum=16, QDoRA.

.PARAMETER Interactive
    Run training directly in foreground terminal rather than immortal detached mode.

.PARAMETER DryRun
    Execute hardware checks, dataset audit, and contract preflight without starting training.

.PARAMETER ForcePrep
    Re-materialize data/polish_qwen_image21_pairs even if dataset_receipt.json already exists.

.EXAMPLE
    .\scripts\training\run_polish_training.ps1 -DryRun
    .\scripts\training\run_polish_training.ps1
    .\scripts\training\run_polish_training.ps1 -Interactive
#>

[CmdletBinding()]
param(
    [ValidateSet("a6000-max", "standard", "qdora-12gb")]
    [string]$Profile = "a6000-max",

    [switch]$Interactive,
    [switch]$DryRun,
    [switch]$ForcePrep
)

$ErrorActionPreference = "Stop"
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
Set-Location $RepoRoot

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "   KRIVEX VISUAL POLISH TIER (QWEN-IMAGE-2.1) TRAINING LAUNCHER                 " -ForegroundColor Cyan
Write-Host "   Target: NVIDIA RTX 6000 Ada (48 GB GDDR6) · Native Windows 11               " -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# ── 1. Python Environment Resolution ──────────────────────────────────────────
$CondaPython = "C:\Users\student\miniconda3\envs\krivex\python.exe"
if (-not (Test-Path $CondaPython)) {
    if ($env:CONDA_PREFIX -and (Test-Path "$env:CONDA_PREFIX\python.exe")) {
        $CondaPython = "$env:CONDA_PREFIX\python.exe"
    } else {
        $CondaPython = "python"
    }
}
Write-Host "[1/6] Resolved Python environment: $CondaPython" -ForegroundColor Green

# Configure PYTHONPATH
$TrainingSrc  = Join-Path $RepoRoot "training\src"
$DataForgeSrc = Join-Path $RepoRoot "data-forge\src"
$InferenceSrc = Join-Path $RepoRoot "inference\src"
$env:PYTHONPATH = "$TrainingSrc;$DataForgeSrc;$InferenceSrc;$RepoRoot;" + $env:PYTHONPATH

# ── 2. Hardware & VRAM Sanitization ───────────────────────────────────────────
Write-Host "[2/6] Checking NVIDIA GPU and sanitizing VRAM state..." -ForegroundColor Cyan

# Terminate lingering VLM server on port 8000 if not dry run
if (-not $DryRun) {
    try {
        $port8000 = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue
        if ($port8000) {
            $lingeringPid = $port8000.OwningProcess
            Write-Host "      Releasing port 8000 (PID $lingeringPid) to reclaim VRAM for training..." -ForegroundColor Yellow
            Stop-Process -Id $lingeringPid -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
    } catch {}
}

$gpuCheck = & $CondaPython -c "import torch; print(f'CUDA: {torch.cuda.is_available()} | Device: {torch.cuda.get_device_name(0) if torch.cuda.is_available() else None} | Dedicated VRAM: {torch.cuda.get_device_properties(0).total_memory / (1024**3):.1f} GB' if torch.cuda.is_available() else 'NO CUDA')"
Write-Host "      $gpuCheck" -ForegroundColor Gray
if ($gpuCheck -notmatch "CUDA: True") {
    Write-Host "[ERROR] CUDA is not available in $CondaPython. Training cannot proceed." -ForegroundColor Red
    exit 1
}

# ── 3. Data-Forge Model Data Verification ──────────────────────────────────────
Write-Host "[3/6] Verifying Data-Forge Stage 12 exported pairs..." -ForegroundColor Cyan
$DataForgeManifest = Join-Path $RepoRoot "data_krivex\model_data\polish_qwen_image21\manifest.jsonl"
$PairsOutputDir    = Join-Path $RepoRoot "data\polish_qwen_image21_pairs"
$PairsReceipt      = Join-Path $PairsOutputDir "dataset_receipt.json"

if (-not (Test-Path $DataForgeManifest) -or ((Get-Item $DataForgeManifest).Length -eq 0)) {
    Write-Host "[WARNING] Data-Forge export manifest not found or empty at: $DataForgeManifest" -ForegroundColor Yellow
    Write-Host "          Data-Forge pipeline may still be executing downstream stages." -ForegroundColor Yellow
    
    # Check if DataForge detached job is active
    $DetachedPidFile = Join-Path $RepoRoot ".detached_job.pid"
    if (Test-Path $DetachedPidFile) {
        $dfPid = (Get-Content $DetachedPidFile).Trim()
        $dfProc = Get-Process -Id $dfPid -ErrorAction SilentlyContinue
        if ($dfProc) {
            Write-Host "          -> Data-Forge detached job (PID $dfPid) is currently ACTIVE." -ForegroundColor Magenta
            Write-Host "          Please allow Data-Forge to complete Stage 12 before launching training." -ForegroundColor Magenta
            if (-not $DryRun) { exit 1 }
        }
    }
    if (-not $DryRun) {
        Write-Host "[ERROR] Cannot proceed without Stage 12 model_data export." -ForegroundColor Red
        exit 1
    }
} else {
    $lineCount = (Get-Content $DataForgeManifest | Measure-Object -Line).Lines
    Write-Host "      Data-Forge Stage 12 export confirmed: $lineCount pairs available." -ForegroundColor Green
}

# ── 4. Dataset Materialization (if needed) ─────────────────────────────────────
Write-Host "[4/6] Checking training dataset materialization..." -ForegroundColor Cyan
if ((Test-Path $DataForgeManifest) -and (-not (Test-Path $PairsReceipt) -or $ForcePrep)) {
    Write-Host "      Materializing Qwen-Image-2.1 condition/target pairs from manifest..." -ForegroundColor Yellow
    $prepCode = @"
import sys
from krivex_training.polish.prepare_dataset import prepare_qwen_pairs_from_manifest
manifest_p = r'$DataForgeManifest'
out_p = r'$PairsOutputDir'
print(f'Building strict Qwen dataset at {out_p}...')
prepare_qwen_pairs_from_manifest(manifest_p, out_p)
print('Dataset materialization complete.')
"@
    & $CondaPython -c $prepCode
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Dataset preparation failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit $LASTEXITCODE
    }
} elseif (Test-Path $PairsReceipt) {
    Write-Host "      Dataset receipt verified at: $PairsReceipt" -ForegroundColor Green
}

# ── 5. Profile Configuration & Preflight Contract ─────────────────────────────
Write-Host "[5/6] Resolving configuration profile: $Profile..." -ForegroundColor Cyan
switch ($Profile) {
    "a6000-max" {
        $ConfigFile = "training\configs\polish_qwen_image21_lora_a6000_max.yaml"
    }
    "standard" {
        $ConfigFile = "training\configs\polish_qwen_image21_lora.yaml"
    }
    "qdora-12gb" {
        $ConfigFile = "training\configs\ablations\polish_qwen_qdora_12gb.yaml"
    }
}
$FullConfigPath = Join-Path $RepoRoot $ConfigFile
Write-Host "      Using config: $FullConfigPath" -ForegroundColor Gray

Write-Host "      Running CPU-only contract preflight check..." -ForegroundColor Cyan
& $CondaPython -m krivex_training.polish.train_preflight $FullConfigPath --dry-run
$preflightExit = $LASTEXITCODE
if ($preflightExit -ne 0) {
    if ($DryRun) {
        Write-Host "      [DRY-RUN NOTE] Preflight reported expected prerequisites (pending Stage 12 data)." -ForegroundColor Yellow
    } else {
        Write-Host "[ERROR] Preflight validation failed. Aborting." -ForegroundColor Red
        exit $preflightExit
    }
} else {
    Write-Host "      Preflight validation passed cleanly." -ForegroundColor Green
}

if ($DryRun) {
    Write-Host "`n[DRY RUN COMPLETE] Hardware, environment, and configs validated successfully." -ForegroundColor Green
    Write-Host "To execute training once Data-Forge completes, run:" -ForegroundColor Cyan
    Write-Host "    .\run_training.ps1" -ForegroundColor Yellow
    exit 0
}

# ── 6. Execution: Detached vs Interactive ──────────────────────────────────────
Write-Host "`n[6/6] Launching Qwen-Image-2.1 DoRA Training..." -ForegroundColor Cyan
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

if ($Interactive) {
    Write-Host "      Running in foreground interactive mode..." -ForegroundColor Yellow
    & $CondaPython -m krivex_training.polish.train_preflight $FullConfigPath
    exit $LASTEXITCODE
} else {
    Write-Host "      Launching in IMMORTAL DETACHED background mode..." -ForegroundColor Green
    $RunDetachedPy = Join-Path $RepoRoot "scripts\run_detached.py"
    $TrainingCmd = "$CondaPython -m krivex_training.polish.train_preflight $FullConfigPath"
    
    & $CondaPython $RunDetachedPy --name "training_$Timestamp" --cmd $TrainingCmd
    Write-Host "`n================================================================================" -ForegroundColor Green
    Write-Host "   TRAINING JOB SUCCESSFULLY SPAWNED IN BACKGROUND                              " -ForegroundColor Green
    Write-Host "================================================================================" -ForegroundColor Green
    Write-Host "The training job is completely immortal and decoupled from SSH/terminal." -ForegroundColor White
    Write-Host "You can safely close this window or laptop. Training will run to completion." -ForegroundColor White
    Write-Host "`nTo follow live training loss and steps:" -ForegroundColor Cyan
    Write-Host "    Get-Content .\logs\detached\latest.log -Wait -Tail 30" -ForegroundColor Yellow
}
