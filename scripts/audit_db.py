
import sqlite3
import os
from pathlib import Path

repo = Path(r"C:\Users\student\Krivex")
db_path = repo / "data_krivex" / "manifests" / "manifest.db"
raw_dir = repo / "data_krivex" / "raw"

print("================================================================")
print("             DATAFORGE FORENSIC AUDIT REPORT                    ")
print("================================================================")

# 1. Manifest DB Query
if db_path.exists():
    conn = sqlite3.connect(str(db_path))
    cursor = conn.cursor()
    
    cursor.execute("SELECT count(*) FROM records")
    total_records = cursor.fetchone()[0]
    print(f"Total Records in Manifest: {total_records}")
    
    cursor.execute("SELECT status, count(*) FROM records GROUP BY status")
    print("Record Status Breakdown:")
    for status, count in cursor.fetchall():
        print(f"  - {status}: {count}")
        
    cursor.execute("SELECT source_dataset, status, count(*) FROM records GROUP BY source_dataset, status")
    print("\nRecords by Dataset:")
    for ds, st, cnt in cursor.fetchall():
        print(f"  - {ds:<18} ({st}): {cnt} records")
        
    conn.close()

# 2. Raw Directory Sizes
print("\n--- 2. RAW DATASETS ON DISK ---")
if raw_dir.exists():
    for d in sorted(raw_dir.iterdir()):
        if d.is_dir():
            # Quick shallow sum of sizes
            total_size = 0
            file_count = 0
            for root, dirs, files in os.walk(d):
                for f in files:
                    if not f.endswith('.lock'):
                        file_count += 1
                        try:
                            total_size += os.path.getsize(os.path.join(root, f))
                        except Exception:
                            pass
            gb = total_size / (1024 * 1024 * 1024)
            print(f"  - {d.name:<18}: {file_count:>6} files | {gb:>7.2f} GB")

# 3. Log Tail
print("\n--- 3. LOG EXECUTION SUMMARY ---")
log_path = repo / "logs" / "data-forge" / "run_20261102_223759.log"
if log_path.exists():
    raw = log_path.read_bytes()
    if raw.startswith(b'\xff\xfe') or (len(raw) > 4 and raw[1:2] == b'\x00' and raw[3:4] == b'\x00'):
        txt = raw.decode('utf-16le', errors='replace')
    else:
        txt = raw.decode('utf-8', errors='replace')
    lines = [l for l in txt.splitlines() if l.strip()]
    print(f"Total Log Lines: {len(lines)}")
    print("Final 20 Lines:")
    for l in lines[-20:]:
        print(f"  {l}")

print("================================================================")
