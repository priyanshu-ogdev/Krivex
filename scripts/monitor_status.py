import os
import sys
import glob
from pathlib import Path
import sqlite3

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

print("=== 1. RUNNING PROCESSES ===")
import subprocess
out = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", 
                      "Get-Process -Name python,powershell | Select-Object Id, ProcessName, CPU, WorkingSet"], 
                     capture_output=True, text=True)
print(out.stdout.strip())

print("\n=== 2. LATEST LOG OUTPUT ===")
log_files = sorted(glob.glob("logs/data-forge/run_*.log"), key=os.path.getmtime)
if log_files:
    latest = log_files[-1]
    print(f"Log: {latest} ({os.path.getsize(latest)} bytes)")
    with open(latest, "r", encoding="utf-8", errors="replace") as f:
        raw = f.read()
        cleaned = raw.replace('\x00', '')
        lines = [l.strip() for l in cleaned.splitlines() if l.strip()]
        for line in lines[-12:]:
            print(line)

print("\n=== 3. RAW DATA VOLUMES ===")
for folder in ["doclaynet", "rico_semantic", "pickapic_v2"]:
    p = Path(f"data_krivex/raw/{folder}")
    if p.exists():
        parquets = list(p.rglob("*.parquet"))
        pngs = list(p.glob("*.png"))
        total_size = sum(f.stat().st_size for f in p.rglob("*") if f.is_file())
        print(f"  raw/{folder:<15}: {len(parquets):>3} parquets | {len(pngs):>6} decoded PNGs | {total_size / (1024*1024):>10.2f} MB")
    else:
        print(f"  raw/{folder:<15}: not created")

pref_p = Path("data_krivex/preference_pairs/pickapic_v2")
if pref_p.exists():
    p_files = list(pref_p.glob("*.json"))
    p_pngs = list(pref_p.glob("*.png"))
    total_pref = sum(f.stat().st_size for f in pref_p.iterdir() if f.is_file())
    print(f"  preference_pairs/pickapic_v2: {len(p_files)} pairs ({len(p_pngs)} PNGs) | {total_pref / (1024*1024):.2f} MB")
else:
    print("  preference_pairs/pickapic_v2: not created")

print("\n=== 4. MANIFEST DB RECORDS ===")
db_path = "data_krivex/manifests/manifest.db"
if os.path.exists(db_path):
    con = sqlite3.connect(db_path)
    cur = con.cursor()
    rows = cur.execute("SELECT source_dataset, status, count(*) FROM records GROUP BY source_dataset, status").fetchall()
    for r in rows:
        print(f"  {r[0]:<20} | status: {r[1]:<20} | count: {r[2]:>7}")
    tot = cur.execute("SELECT count(*) FROM records").fetchone()[0]
    print(f"  Total Ingested Records: {tot}")
    con.close()
