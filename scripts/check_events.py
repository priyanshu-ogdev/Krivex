
import json
import sys
from pathlib import Path

repo = Path(r"C:\Users\student\Krivex")
log_path = repo / "logs" / "data-forge" / "run_20261102_223759.log"

raw = log_path.read_bytes()
if raw.startswith(b'\xff\xfe') or (len(raw) > 4 and raw[1:2] == b'\x00' and raw[3:4] == b'\x00'):
    txt = raw.decode('utf-16le', errors='replace')
else:
    txt = raw.decode('utf-8', errors='replace')

dataset_events = {}
for line in txt.splitlines():
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        data = json.loads(line)
        ds = data.get("dataset")
        ev = data.get("event")
        if ds:
            dataset_events.setdefault(ds, []).append((ev, data.get("level"), data.get("note") or data.get("error") or ""))
    except Exception:
        pass

print("=== DATASET EVENT SUMMARY IN LOG ===")
for ds, evs in dataset_events.items():
    print(f"\n[{ds}] ({len(evs)} events):")
    for ev, lvl, detail in evs[:5]:
        det = f" -- {detail[:80]}" if detail else ""
        print(f"  - {lvl.upper() if lvl else 'INFO'}: {ev}{det}")
    if len(evs) > 5:
        print(f"  ... and {len(evs)-5} more events ...")
        for ev, lvl, detail in evs[-2:]:
            det = f" -- {detail[:80]}" if detail else ""
            print(f"  - {lvl.upper() if lvl else 'INFO'}: {ev}{det}")
