# Project Deployment & Setup TODO

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
