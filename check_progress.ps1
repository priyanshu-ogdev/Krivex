<#
.SYNOPSIS
    Real-Time Data-Forge Pipeline Monitor & Stage 12 Completion Verifier.
.DESCRIPTION
    Checks detached job process health, manifest status counts, VLM activity,
    and Stage 12 model-data export verification.
#>

[CmdletBinding()]
param()

$RepoRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
Set-Location $RepoRoot

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "   KRIVEX DATA-FORGE: REAL-TIME PIPELINE PROGRESS & STAGE 12 VERIFIER            " -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# ── 1. Process Status ──────────────────────────────────────────────────────────
$PidFile = Join-Path $RepoRoot ".detached_job.pid"
$isJobActive = $false
$jobPid = $null

if (Test-Path $PidFile) {
    $jobPid = (Get-Content $PidFile).Trim()
    $proc = Get-Process -Id $jobPid -ErrorAction SilentlyContinue
    if ($proc) {
        $isJobActive = $true
        $wsMb = [math]::Round($proc.WorkingSet64 / 1MB, 1)
        Write-Host ">> Process State : ACTIVE (PID: $jobPid, WorkingSet: $wsMb MB)" -ForegroundColor Green
    } else {
        Write-Host ">> Process State : COMPLETED / INACTIVE (Last PID: $jobPid)" -ForegroundColor Yellow
    }
} else {
    Write-Host ">> Process State : NO DETACHED JOB PID FOUND" -ForegroundColor Gray
}

# ── 2. Manifest Breakdown ──────────────────────────────────────────────────────
$ManifestDb = Join-Path $RepoRoot "data_krivex\manifests\manifest.db"
$Python = "C:\Users\student\miniconda3\envs\krivex-data\python.exe"
if (-not (Test-Path $Python)) { $Python = "python" }

if (Test-Path $ManifestDb) {
    Write-Host "`n--- Manifest Database Status ---" -ForegroundColor Cyan
    $queryCode = @'
import sqlite3
import sys

manifest_p = sys.argv[1]
try:
    conn = sqlite3.connect(manifest_p)
    c = conn.cursor()
    c.execute('SELECT status, count(*) FROM records GROUP BY status')
    rows = c.fetchall()
    total = sum(r[1] for r in rows)
    
    non_dup = sum(r[1] for r in rows if r[0] != 'excluded_duplicate')
    in_pipeline = sum(r[1] for r in rows if r[0] not in ('deduped', 'excluded_duplicate'))
    pct = (in_pipeline / non_dup * 100.0) if non_dup > 0 else 0.0
    
    print(f'Total Records in Manifest : {total:,}')
    print(f'Target Deduplicated Pool  : {non_dup:,} (excluding {total-non_dup:,} duplicates)')
    print(f'Advanced Past Stage 2     : {in_pipeline:,} / {non_dup:,} ({pct:.1f}% progressed)\n')
    
    print('Breakdown by Status:')
    for status, count in sorted(rows, key=lambda x: -x[1]):
        print(f'  {status:<24} : {count:>7,}')
    conn.close()
except Exception as e:
    print('Error querying manifest:', e)
'@
    & $Python -c $queryCode $ManifestDb
} else {
    Write-Host "[WARNING] Manifest DB not found at $ManifestDb" -ForegroundColor Yellow
}

# ── 3. Stage 10 & Stage 12 Verification ────────────────────────────────────────
Write-Host "`n--- Downstream Stage Verification ---" -ForegroundColor Cyan
$Stage10Report  = Join-Path $RepoRoot "data_krivex\audit_reports"
$Stage12Export  = Join-Path $RepoRoot "data_krivex\model_data\polish_qwen_image21\manifest.jsonl"
$Stage12Summary = Join-Path $RepoRoot "data_krivex\model_data\polish_qwen_image21\manifest_summary.json"

$hasAudit = Test-Path $Stage10Report
$hasExport = $false
if (Test-Path $Stage12Export) {
    $item = Get-Item $Stage12Export
    if ($item.Length -gt 0) {
        $hasExport = $true
    }
}

if ($hasAudit) {
    Write-Host "  [OK] Stage 10 (VLM Audit Gate)     : Reports generated under data_krivex/audit_reports" -ForegroundColor Green
} else {
    Write-Host "  [..] Stage 10 (VLM Audit Gate)     : In queue (executes after Stage 9)" -ForegroundColor Gray
}

if ($hasExport) {
    $pairCount = (Get-Content $Stage12Export | Measure-Object -Line).Lines
    Write-Host "  [OK] Stage 12 (Model Data Export)  : COMPLETE ($pairCount pair records exported)" -ForegroundColor Green
    Write-Host "`n================================================================================" -ForegroundColor Green
    Write-Host "   STAGE 12 IS FULLY COMPLETE! DATASET IS READY FOR TRAINING!                    " -ForegroundColor Green
    Write-Host "================================================================================" -ForegroundColor Green
    Write-Host "Next Step: You can now launch the training pipeline by executing:" -ForegroundColor Cyan
    Write-Host "    .\run_training.ps1" -ForegroundColor Yellow
} else {
    Write-Host "  [..] Stage 12 (Model Data Export)  : IN PROGRESS / AWAITING DOWNSTREAM" -ForegroundColor Gray
    if ($isJobActive) {
        Write-Host "`n-> Data-Forge is actively processing. Stage 12 will automatically populate upon completion." -ForegroundColor Yellow
        Write-Host "   To tail live pipeline logs:" -ForegroundColor Cyan
        Write-Host "       Get-Content .\data_krivex\logs\pipeline.jsonl -Wait -Tail 20" -ForegroundColor Gray
    } else {
        Write-Host "`n-> Process is inactive. Inspect latest job log for errors:" -ForegroundColor Red
        Write-Host "       Get-Content .\logs\detached\latest.log -Tail 50" -ForegroundColor Red
    }
}

# ── 4. GPU Hardware Status ─────────────────────────────────────────────────────
Write-Host "`n--- GPU Hardware State ---" -ForegroundColor Cyan
try {
    nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader | ForEach-Object {
        $parts = $_.Split(",")
        Write-Host "  GPU          : $($parts[0].Trim())" -ForegroundColor White
        Write-Host "  Utilization  : $($parts[1].Trim())" -ForegroundColor White
        Write-Host "  VRAM Used    : $($parts[2].Trim()) / $($parts[3].Trim())" -ForegroundColor White
        Write-Host "  Temperature  : $($parts[4].Trim()) C" -ForegroundColor White
    }
} catch {
    Write-Host "  (nvidia-smi unavailable)" -ForegroundColor Gray
}
Write-Host "================================================================================`n" -ForegroundColor Cyan
