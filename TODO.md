# Project Deployment & Setup TODO

## Active Operations: Data-Forge Completion & Training Launch Runbook

---

### Step A: Monitor Real-Time Data-Forge Progress
Connect via SSH to the server and execute the real-time verifier:
\\powershell
ssh Student@100.126.34.68
# Password: WarriorEX1*

cd C:\Users\student\Krivex
.\check_progress.ps1
\- **What this tells you**:
  - Process State (\ACTIVE\ with PID or \COMPLETED\).
  - Total records processed past Stage 2 (dedup / quality / PII / safety).
  - Exact breakdown of manifest statuses.
  - Stage 10 (VLM Audit Gate) and Stage 12 (Model Data Export) completion status.
  - Current GPU VRAM allocation.

To follow the live log stream in real time:
\\powershell
Get-Content .\data_krivex\logs\pipeline.jsonl -Wait -Tail 20
\
---

### Step B: How to Know Stage 12 is Completely Done
Stage 12 is finished when **both** of the following conditions are met:
1. \.\check_progress.ps1\ displays:
   \   [OK] Stage 12 (Model Data Export)  : COMPLETE (... pair records exported)
   STAGE 12 IS FULLY COMPLETE! DATASET IS READY FOR TRAINING!
   \2. The export manifest exists and is non-empty:
   \\powershell
   Test-Path .\data_krivex\model_data\polish_qwen_image21\manifest.jsonl
   # Returns: True
   \3. The detached job log shows exit code 0:
   \\powershell
   Get-Content .\logs\detached\latest.log -Tail 10
   # Returns: [JOB_RUNNER] Completed ... with Exit Code 0
   \
---

### Step C: Flush & Verify GPU VRAM
Before starting training, the 48 GB RTX 6000 Ada GPU must be completely free (0 MB allocated), so the 45 GB DoRA profile has full headroom:
\\powershell
nvidia-smi
\- If any old VLM server or Python process is still holding VRAM:
  \\powershell
  Get-Process -Name python, cmd -ErrorAction SilentlyContinue | Where-Object { \.Id -ne \9860 }
  # Stop lingering processes if necessary:
  # Stop-Process -Id <PID> -Force
  \
---

### Step D: Launch Visual Polish Tier (Qwen-Image-2.1 DoRA) Training
Activate the verified training environment and start training:

#### 1. Activate Conda Environment
\\powershell
conda activate krivex
\*(Python 3.11.18, PyTorch 2.11.0+cu126, Diffusers efe46a5, Accelerate 1.15.0, PEFT 0.21.2)*

#### 2. Launch Production Training (Immortal Detached Mode - Recommended)
*Runs in the background completely decoupled from your SSH session. You can close your laptop.*
\\powershell
.\run_training.ps1
\*(By default uses the Enterprise Max profile: batch 16, accum 2 = effective 32, rank 128 DoRA, fp32 AdamW, peak 45.0 GB VRAM).*

To stream live training loss & steps:
\\powershell
Get-Content .\logs\detached\latest.log -Wait -Tail 30
\
#### 3. (Alternative) Launch in Foreground Interactive Mode
*If you want to view progress bars and loss directly in the active terminal window:*
\\powershell
.\run_training.ps1 -Interactive
\
---

## RTX 6000 Headless Remote Server Setup

- [ ] **Step 1: Execute Master Setup Script on Server**
  - Run the following unified script in an **Administrator PowerShell** on the RTX 6000 server machine (`100.126.34.68`).
  - Covers: port 22 conflict resolution, OpenSSH host key repair, `Student` account lock, firewall configuration, Tailscale unattended boot, 24/7 power lockdown, and Windows Update suppression.

```powershell
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "   RTX 6000 Server: Master SSH & 24/7 Unattended Setup          " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# 1. Clear Rogue WSL Port Forwarding & Conflicting SSH Services on Port 22
# ------------------------------------------------------------------------------
Write-Host "[1/7] Removing conflicting port proxies and WSL SSH services..." -ForegroundColor Yellow
netsh interface portproxy reset | Out-Null
Get-Service -Name "WSL_SSH*" -ErrorAction SilentlyContinue | Stop-Service -Force
Get-Service -Name "WSL_SSH*" -ErrorAction SilentlyContinue | Set-Service -StartupType Disabled

# ------------------------------------------------------------------------------
# 2. Repair OpenSSH Server & Regenerate Host Keys (Fixes Connection Reset)
# ------------------------------------------------------------------------------
Write-Host "[2/7] Resetting OpenSSH host keys and service recovery..." -ForegroundColor Yellow
Stop-Service sshd -Force -ErrorAction SilentlyContinue

# Delete corrupted host keys so sshd regenerates them with strict SYSTEM ACLs
Remove-Item -Path "C:\ProgramData\ssh\ssh_host_*_key*" -Force -ErrorAction SilentlyContinue

Set-Service -Name "sshd" -StartupType Automatic
Set-Service -Name "ssh-agent" -StartupType Automatic
sc.exe failure sshd reset= 86400 actions= restart/5000/restart/5000/restart/5000 | Out-Null

# ------------------------------------------------------------------------------
# 3. Verify & Lock 'Student' SSH Account
# ------------------------------------------------------------------------------
Write-Host "[3/7] Configuring 'Student' account with non-expiring password..." -ForegroundColor Yellow
$userExists = Get-LocalUser -Name "Student" -ErrorAction SilentlyContinue
if (-not $userExists) {
    net user Student "WarriorEX1*" /add | Out-Null
    net localgroup Users Student /add | Out-Null
} else {
    net user Student "WarriorEX1*" | Out-Null
}
Enable-LocalUser -Name "Student" -ErrorAction SilentlyContinue
Set-LocalUser -Name "Student" -PasswordNeverExpires $true

# ------------------------------------------------------------------------------
# 4. Open Port 22 Across All Windows Firewall Profiles
# ------------------------------------------------------------------------------
Write-Host "[4/7] Opening Port 22 on Windows Defender Firewall..." -ForegroundColor Yellow
Remove-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' `
    -DisplayName 'OpenSSH Server (sshd)' `
    -Enabled True `
    -Direction Inbound `
    -Protocol TCP `
    -Action Allow `
    -Profile Any `
    -LocalPort 22 | Out-Null

# ------------------------------------------------------------------------------
# 5. Lock Tailscale into Unattended Always-On Mode
# ------------------------------------------------------------------------------
Write-Host "[5/7] Enabling Tailscale Unattended Mode & crash recovery..." -ForegroundColor Yellow
Set-Service -Name "Tailscale" -StartupType Automatic
Start-Service Tailscale -ErrorAction SilentlyContinue
tailscale up --unattended --reset
sc.exe failure Tailscale reset= 86400 actions= restart/5000/restart/5000/restart/5000 | Out-Null

# ------------------------------------------------------------------------------
# 6. Disable System Sleep, Hibernate, and NIC Power Saving
# ------------------------------------------------------------------------------
Write-Host "[6/7] Disabling system sleep, hibernate, and network card sleep..." -ForegroundColor Yellow
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change hibernate-timeout-ac 0
powercfg /change monitor-timeout-ac 0
powercfg -h off
powercfg -setacvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 0
powercfg -setacvalueindex SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE 0
powercfg -SetActive SCHEME_CURRENT

Get-NetAdapter | ForEach-Object {
    Disable-NetAdapterPowerManagement -Name $_.Name -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------------------------
# 7. Prevent Windows Update Auto-Reboots & Start OpenSSH
# ------------------------------------------------------------------------------
Write-Host "[7/7] Blocking Windows Update auto-reboots and starting sshd..." -ForegroundColor Yellow
$auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
if (-not (Test-Path $auPath)) {
    New-Item -Path $auPath -Force | Out-Null
}
Set-ItemProperty -Path $auPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord
Set-ItemProperty -Path $auPath -Name "AUOptions" -Value 2 -Type DWord

Start-Service sshd

Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "   VERIFICATION AUDIT                                           " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Get-Service -Name Tailscale, sshd | Select-Object Name, Status, StartType | Format-Table -AutoSize
Get-NetTCPConnection -LocalPort 22 -State Listen | Select-Object LocalAddress, LocalPort, OwningProcess | Format-Table -AutoSize
Write-Host "Tailscale IP: $(tailscale ip -4)" -ForegroundColor Cyan
```

---

- [ ] **Step 2: Local Verification on the Server**
  - Run from the same PowerShell window on the server:
  ```powershell
  ssh -o StrictHostKeyChecking=no Student@127.0.0.1
  ```
  - Enter password: `WarriorEX1*`
  - Once verified, type `exit`.

---

- [ ] **Step 3: Remote Connection from Client / Laptop**
  - Connect to the Windows host:
  ```powershell
  ssh Student@100.126.34.68
  ```
  - Direct drop-in into WSL Ubuntu:
  ```powershell
  ssh -t Student@100.126.34.68 "wsl -u priyanshu"
  ```

---

- [ ] **Step 4: Machine Learning Stack & Training Initialization**
  - [ ] Verify NVIDIA GPU in WSL: `nvidia-smi` (Confirm RTX 6000 48GB GDDR6 VRAM, CUDA Driver 13.2).
  - [ ] Initialize Python 3.11 environment: `conda create -n krivex python=3.11 -y && conda activate krivex`
  - [ ] Install sealed PyTorch 2.11: `pip install "torch>=2.11.0,<2.12.0" "torchvision>=0.26.0,<0.27.0" --index-url https://download.pytorch.org/whl/cu124`
  - [ ] Install vLLM 0.29: `pip install "vllm==0.29.0"`
  - [ ] Install Krivex monorepo packages:
    ```bash
    pip install -e "./data-forge[dev]"
    pip install -e "./training[dev,polish]"
    pip install -e "./inference[dev,backends]"
    ```
  - [ ] Run pre-flight read-only audit:
    ```bash
    python scripts/training/audit_training_pipeline.py
    ```

---

- [ ] **Step 5: 100% Native Windows Background Execution (nohup & tmux Alternative)**
  - **Why**: Windows has no built-in `tmux`, and closing an SSH session kills foreground processes. We built a native PowerShell background manager (`scripts/run_detached.ps1`) that runs jobs completely decoupled from the SSH session. No Linux or WSL required.
  
  - **1. Launch Training in Background (Survives SSH Disconnects)**:
    ```powershell
    .\scripts
un_detached.ps1 -Start ".\scripts	raining	rain_all.ps1 -Tier polish-default" -Log "training.log"
    ```
    *(You can now safely exit SSH or close your laptop. Training continues running on the RTX 6000).*

  - **2. Stream Live Progress ('tmux attach' Equivalent)**:
    ```powershell
    .\scripts
un_detached.ps1 -Follow
    ```
    *(Press `Ctrl + C` anytime to detach. The job continues running in the background).*

  - **3. Check Job Health & Hardware Metrics**:
    ```powershell
    .\scripts
un_detached.ps1 -Status
    ```

  - **4. Stop or Terminate Job**:
    ```powershell
    .\scripts
un_detached.ps1 -Stop
    ```

  - *(Optional WSL tmux alternative)*:
    If you ever decide to run inside WSL Ubuntu instead:
    ```bash
    tmux new -s train
    ./scripts/training/train.sh polish-default
    # Detach: Ctrl+B, D | Reattach: tmux attach -t train
    ```
