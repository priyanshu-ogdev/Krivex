<#
.SYNOPSIS
    Clone and configure the pinned Hugging Face diffusers checkout and Qwen-Image-2.1 DreamBooth dependencies.
.PARAMETER DiffusersDir
    Destination path for diffusers checkout (default: ./third_party/diffusers).
#>

[CmdletBinding()]
param(
    [string]$DiffusersDir = "",
    [string]$DiffusersRevision = "efe46a5b177af67c64b3666da8ddddac7ee12163"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
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
$LogFile = Join-Path $LogDir "diffusers_setup_$Timestamp.log"
Start-Transcript -Path $LogFile -Append | Out-Null
Write-Host "[LOG] Full stdout & stderr captured to: $LogFile" -ForegroundColor DarkGray

if (-not $DiffusersDir) {
    $DiffusersDir = "$RepoRoot\third_party\diffusers"
}

Write-Host "Preparing pinned diffusers repository (pinned Qwen-Image-2.1 training script)..." -ForegroundColor Cyan

if (-not (Test-Path $DiffusersDir)) {
    $parent = Split-Path -Parent $DiffusersDir
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    git clone https://github.com/huggingface/diffusers.git "$DiffusersDir"
} else {
    Write-Host "Diffusers already cloned at $DiffusersDir." -ForegroundColor DarkGray
}

$head = (git -C "$DiffusersDir" rev-parse HEAD).Trim()
$dirty = (git -C "$DiffusersDir" status --porcelain --untracked-files=all)
if ($head -ne $DiffusersRevision) {
    if ($dirty) {
        throw "Refusing to change dirty Diffusers checkout at $DiffusersDir (HEAD $head; expected $DiffusersRevision)."
    }
    git -C "$DiffusersDir" fetch origin "$DiffusersRevision"
    git -C "$DiffusersDir" checkout --detach "$DiffusersRevision"
}

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

$Pip = ""
$pyDir = Split-Path -Parent $Python
$candidatePip = Join-Path $pyDir "Scripts\pip.exe"
if (Test-Path $candidatePip) {
    $Pip = $candidatePip
} elseif (Test-Path (Join-Path $pyDir "pip.exe")) {
    $Pip = Join-Path $pyDir "pip.exe"
} else {
    $Pip = "pip"
}

Write-Host "Installing diffusers in editable mode..." -ForegroundColor DarkGray
& $Pip install -e "$DiffusersDir"

$dreamboothReq = "$DiffusersDir\examples\dreambooth\requirements.txt"
if (Test-Path $dreamboothReq) {
    Write-Host "Installing DreamBooth requirements..." -ForegroundColor DarkGray
    & $Pip install -r "$dreamboothReq"
}

$zimageReq = "$DiffusersDir\examples\dreambooth\requirements_z_image.txt"
if (Test-Path $zimageReq) {
    Write-Host "Installing Z-Image specific requirements..." -ForegroundColor DarkGray
    & $Pip install -r "$zimageReq"
}

Write-Host "Installing pinned training dependencies..." -ForegroundColor DarkGray
& $Pip install "accelerate==1.10.1" "peft==0.17.1" "datasets>=3.0.0" "pyarrow==21.0.0"

$trainerScript = "$DiffusersDir\examples\dreambooth\train_dreambooth_lora_qwenimage21_img2img.py"
if (Test-Path $trainerScript) {
    Write-Host "Verifying and applying native DoRA patch to Qwen-Image-2.1 trainer..." -ForegroundColor DarkGray
    $py = "$RepoRoot\.venv\Scripts\python.exe"
    if (-not (Test-Path $py)) { $py = "python" }
    & $py -c @"
import sys
from pathlib import Path

script_path = Path(r'$trainerScript')
if not script_path.is_file():
    sys.exit(0)
content = script_path.read_text(encoding='utf-8')
if '--use_dora' not in content:
    arg_target = 'parser.add_argument(\"--lora_dropout\", type=float, default=0.0, help=\"Dropout probability for LoRA layers\")'
    dora_arg = '\n    parser.add_argument(\n        \"--use_dora\",\n        action=\"store_true\",\n        default=False,\n        help=\"Whether to use DoRA (Weight-Decomposed Low-Rank Adaptation) instead of standard LoRA.\",\n    )'
    if arg_target in content:
        content = content.replace(arg_target, arg_target + dora_arg)
    else:
        sys.exit('Missing parser lora_dropout anchor')

    lora_target = 'init_lora_weights=\"gaussian\",\n        target_modules=target_modules,'
    dora_lora = 'init_lora_weights=\"gaussian\",\n        target_modules=target_modules,\n        use_dora=args.use_dora,'
    if lora_target in content:
        content = content.replace(lora_target, dora_lora)
    else:
        sys.exit('Missing LoraConfig target_modules anchor')

    script_path.write_text(content, encoding='utf-8')
    print('Successfully applied native DoRA patch to ' + str(script_path))
else:
    print('Native DoRA patch already present in ' + str(script_path))
"@
}

Write-Host "`n[SUCCESS] Diffusers training environment configured." -ForegroundColor Green
Write-Host "Official Qwen-Image-2.1 LoRA script located at:" -ForegroundColor DarkGray
Write-Host "    $DiffusersDir\examples\dreambooth\train_dreambooth_lora_qwenimage21_img2img.py" -ForegroundColor DarkGray
Write-Host "Run 'accelerate config' if you have not configured accelerate yet." -ForegroundColor Yellow
try {
    Stop-Transcript | Out-Null
    Copy-Item $LogFile (Join-Path $LogDir "latest.log") -Force -ErrorAction SilentlyContinue
    Copy-Item $LogFile (Join-Path (Join-Path $RepoRoot "logs") "latest.log") -Force -ErrorAction SilentlyContinue
} catch {}
