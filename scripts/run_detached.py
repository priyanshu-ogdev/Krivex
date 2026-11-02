#!/usr/bin/env python3
"""Native Windows Detached Background Process Manager (Immortal Process Runner).

Runs long-running training, data-forge, or inference jobs in a persistent, detached background
process that breaks away from OpenSSH Job Objects and survives SSH disconnects, laptop lid closes,
and network drops. Automatically captures ALL streams (stdout, stderr, warnings) into timestamped
log files under logs/ and maintains symlinks/copies to latest.log.

Usage:
    python scripts/run_detached.py --start "powershell -ExecutionPolicy Bypass -File scripts/training/train_all.ps1 -Tier polish-default"
    python scripts/run_detached.py --status
    python scripts/run_detached.py --follow
    python scripts/run_detached.py --list-logs
    python scripts/run_detached.py --stop
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

# Win32 Process Creation Flags
CREATE_BREAKAWAY_FROM_JOB = 0x01000000
CREATE_NEW_PROCESS_GROUP = 0x00000200
DETACHED_PROCESS = 0x00000008

ROOT = Path(__file__).resolve().parents[1]
META_FILE = ROOT / ".detached_job.json"
LEGACY_PID_FILE = ROOT / ".detached_job.pid"
LOGS_DIR = ROOT / "logs"
DETACHED_LOGS_DIR = LOGS_DIR / "detached"


def _format_size(size_bytes: int) -> str:
    if size_bytes < 1024:
        return f"{size_bytes} B"
    elif size_bytes < 1024 * 1024:
        return f"{size_bytes / 1024:.1f} KB"
    else:
        return f"{size_bytes / (1024 * 1024):.1f} MB"


def _list_logs() -> int:
    print("=" * 64)
    print("   Krivex Execution Logs (logs/)")
    print("=" * 64)
    if not LOGS_DIR.is_dir():
        print("No logs directory found.")
        return 0

    log_files = sorted(LOGS_DIR.rglob("*.log"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not log_files:
        print("No log files found in logs/.")
        return 0

    print(f"{'Relative Path':<45} {'Size':<10} {'Last Modified':<20}")
    print("-" * 75)
    for p in log_files:
        rel = str(p.relative_to(ROOT))
        stat = p.stat()
        mtime = datetime.datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M:%S")
        size_str = _format_size(stat.st_size)
        print(f"{rel:<45} {size_str:<10} {mtime:<20}")
    return 0


def _stop() -> int:
    meta = None
    pid = None
    log_file = None
    if META_FILE.is_file():
        try:
            meta = json.loads(META_FILE.read_text(encoding="utf-8"))
            pid = meta.get("pid")
            log_file = meta.get("log_file")
        except Exception:
            pass
    elif LEGACY_PID_FILE.is_file():
        try:
            pid = int(LEGACY_PID_FILE.read_text(encoding="utf-8").strip())
        except Exception:
            pass

    if not pid:
        print("[!] No active detached job registered.")
        return 0

    print(f"[*] Terminating detached job (PID: {pid})...")
    if sys.platform == "win32":
        # Force terminate process tree using taskkill
        subprocess.run(["taskkill", "/F", "/T", "/PID", str(pid)], capture_output=True)
    else:
        try:
            os.kill(pid, 9)
        except OSError:
            pass

    if log_file and Path(log_file).is_file():
        now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with open(log_file, "a", encoding="utf-8") as f:
            f.write(f"\n=== Detached Job Terminated Manually at {now_str} ===\n")

    META_FILE.unlink(missing_ok=True)
    LEGACY_PID_FILE.unlink(missing_ok=True)
    print("[SUCCESS] Detached job terminated.")
    return 0


def _is_running(pid: int) -> bool:
    if sys.platform == "win32":
        res = subprocess.run(
            ["tasklist", "/FI", f"PID eq {pid}", "/NH"],
            capture_output=True,
            text=True,
        )
        return str(pid) in res.stdout
    else:
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False


def _status() -> int:
    if not META_FILE.is_file():
        print("[i] No active detached job registered in .detached_job.json.")
        return 0

    try:
        meta = json.loads(META_FILE.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"[ERROR] Failed to read metadata: {e}")
        return 1

    pid = meta.get("pid")
    cmd = meta.get("command")
    start_time = meta.get("start_time")
    log_file = meta.get("log_file")

    running = _is_running(pid) if pid else False

    print("=" * 64)
    if running:
        print(f"   Detached Job ACTIVE (PID: {pid})")
    else:
        print(f"   Detached Job FINISHED / COMPLETED (PID: {pid})")
    print("=" * 64)
    print(f"Command   : {cmd}")
    print(f"Started   : {start_time}")
    print(f"Log File  : {log_file}")
    print(f"Status    : {'RUNNING' if running else 'COMPLETED'}")

    if log_file and Path(log_file).is_file():
        print(f"\n--- Recent Log Output ({Path(log_file).name}) ---")
        try:
            lines = Path(log_file).read_text(encoding="utf-8", errors="replace").splitlines()
            tail = lines[-15:] if len(lines) > 15 else lines
            for l in tail:
                print(f"  {l}")
        except Exception:
            pass

    if not running:
        META_FILE.unlink(missing_ok=True)
        LEGACY_PID_FILE.unlink(missing_ok=True)

    return 0


def _follow(log_path: str | None = None) -> int:
    target = None
    if log_path:
        target = Path(log_path).resolve()
    elif META_FILE.is_file():
        try:
            meta = json.loads(META_FILE.read_text(encoding="utf-8"))
            if meta.get("log_file"):
                target = Path(meta["log_file"]).resolve()
        except Exception:
            pass

    if not target or not target.is_file():
        latest = DETACHED_LOGS_DIR / "latest.log"
        if latest.is_file():
            target = latest
        else:
            root_latest = LOGS_DIR / "latest.log"
            if root_latest.is_file():
                target = root_latest

    if not target or not target.is_file():
        print("[ERROR] No active or latest log file found.")
        return 1

    print("=" * 64)
    print(f"   Streaming Live Log: {target}")
    print("=" * 64)
    print("[i] Press Ctrl+C anytime to detach. (Job will keep running safely in background!)")
    print("-" * 64)

    try:
        with open(target, "r", encoding="utf-8", errors="replace") as f:
            # Print initial contents
            content = f.read()
            sys.stdout.write(content)
            sys.stdout.flush()
            while True:
                line = f.readline()
                if line:
                    sys.stdout.write(line)
                    sys.stdout.flush()
                else:
                    time.sleep(0.5)
    except KeyboardInterrupt:
        print("\n[i] Safely detached. Background job continues running.")
        return 0


def _start(command: str, custom_log: str | None = None) -> int:
    # Check if a detached job is already active
    if META_FILE.is_file():
        try:
            old_meta = json.loads(META_FILE.read_text(encoding="utf-8"))
            old_pid = old_meta.get("pid")
            if old_pid and _is_running(old_pid):
                print(f"[ERROR] A detached job is already running with PID {old_pid}.")
                print(f"Command: {old_meta.get('command')}")
                print("Run 'python scripts/run_detached.py --stop' to terminate it first.")
                return 1
        except Exception:
            pass

    DETACHED_LOGS_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    if custom_log:
        log_path = Path(custom_log).resolve()
    else:
        log_path = (DETACHED_LOGS_DIR / f"job_{timestamp}.log").resolve()

    log_path.parent.mkdir(parents=True, exist_ok=True)

    header = f"""================================================================================
KRIVEX IMMORTAL DETACHED RUN
Started At : {now_str}
Command    : {command}
Log File   : {log_path}
Streams    : All Streams Captured (stdout, stderr, warnings, exceptions)
================================================================================
"""
    log_path.write_text(header, encoding="utf-8")

    # Generate a dedicated runner script to ensure clean execution and avoid argument escaping problems
    runner_script = DETACHED_LOGS_DIR / f"_runner_{timestamp}.bat"
    
    # Normalize command for execution in Windows cmd/bat wrapper:
    # If a .ps1 script or relative PowerShell command is given without 'powershell', wrap it
    cmd_trimmed = command.strip()
    cmd_lower = cmd_trimmed.lower()
    exec_cmd = command
    if not (cmd_lower.startswith("powershell") or cmd_lower.startswith("python") or cmd_lower.startswith("cmd")):
        if ".ps1" in cmd_lower or cmd_trimmed.startswith(".\\") or cmd_trimmed.startswith("./"):
            exec_cmd = f'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& {{ [Console]::OutputEncoding=[System.Text.Encoding]::UTF8; {command} }}"'

    # Bat runner sets code page to UTF-8, enters root, runs command redirecting all output, and appends completion banner
    bat_content = f"""@echo off
chcp 65001 >nul
cd /d "{ROOT}"
echo [JOB_RUNNER] Process started at %date% %time% >> "{log_path}"
{exec_cmd} >> "{log_path}" 2>&1
set EXIT_CODE=%ERRORLEVEL%
echo. >> "{log_path}"
echo ================================================================================ >> "{log_path}"
echo [JOB_RUNNER] Completed at %date% %time% with Exit Code %EXIT_CODE% >> "{log_path}"
echo ================================================================================ >> "{log_path}"
del "%~f0" >nul 2>&1
exit /b %EXIT_CODE%
"""
    runner_script.write_text(bat_content, encoding="utf-8")

    creation_flags = 0
    if sys.platform == "win32":
        creation_flags = CREATE_BREAKAWAY_FROM_JOB | DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP

    proc = subprocess.Popen(
        [str(runner_script)],
        cwd=str(ROOT),
        creationflags=creation_flags,
        close_fds=True,
    )

    meta = {
        "pid": proc.pid,
        "command": command,
        "start_time": now_str,
        "log_file": str(log_path),
    }
    META_FILE.write_text(json.dumps(meta, indent=2), encoding="utf-8")
    LEGACY_PID_FILE.write_text(str(proc.pid), encoding="utf-8")

    # Update latest.log pointers
    try:
        shutil.copyfile(log_path, DETACHED_LOGS_DIR / "latest.log")
        shutil.copyfile(log_path, LOGS_DIR / "latest.log")
    except Exception:
        pass

    print("=" * 64)
    print(f"   IMMORTAL JOB SPAWNED (PID: {proc.pid})")
    print("=" * 64)
    print(f"Command   : {command}")
    print(f"Log File  : {log_path}")
    print("Streams   : All (stdout, stderr, warnings) -> Dedicated Log File")
    print("\n[SAFE TO DISCONNECT] Process broke away from SSH Job Object.")
    print("You can exit SSH, close your laptop, or reboot client machine freely!")
    print("\nOperational Commands:")
    print("  Follow output  : python scripts/run_detached.py --follow")
    print("  Check status   : python scripts/run_detached.py --status")
    print("  List logs      : python scripts/run_detached.py --list-logs")
    print("  Stop job       : python scripts/run_detached.py --stop")
    print("  PowerShell equiv: .\\scripts\\run_detached.ps1 -Follow / -Status / -Stop")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Native Windows Detached Background Process Manager (Immortal Process Runner)."
    )
    parser.add_argument("--start", type=str, help="Command to execute in the background.")
    parser.add_argument("--log", type=str, help="Custom log path.")
    parser.add_argument("--status", action="store_true", help="Display active job metrics and log tail.")
    parser.add_argument("--follow", action="store_true", help="Live stream log output.")
    parser.add_argument("--stop", action="store_true", help="Stop running detached job.")
    parser.add_argument("--list-logs", action="store_true", help="List all logs in logs/.")

    args = parser.parse_args()

    if args.list_logs:
        return _list_logs()
    elif args.stop:
        return _stop()
    elif args.status:
        return _status()
    elif args.follow:
        return _follow(args.log)
    elif args.start:
        return _start(args.start, args.log)
    else:
        parser.print_help()
        return 0


if __name__ == "__main__":
    raise SystemExit(main())

