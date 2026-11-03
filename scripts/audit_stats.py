
import sqlite3
import os
import json
from pathlib import Path

db_path = "C:/Users/student/Krivex/data_krivex/manifests/manifest.db"
conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
cur = conn.cursor()

cur.execute("PRAGMA table_info(records)")
cols = [r["name"] for r in cur.fetchall()]

# 1. Status breakdown
cur.execute("SELECT status, count(*) FROM records GROUP BY status")
status_counts = dict(cur.fetchall())

# 2. Dataset breakdown
ds_col = "dataset" if "dataset" in cols else ("source_dataset" if "source_dataset" in cols else "domain")
cur.execute(f"SELECT {ds_col}, count(*) FROM records GROUP BY {ds_col}")
source_counts = dict(cur.fetchall())

# 3. Deduped by dataset
cur.execute(f"SELECT {ds_col}, count(*) FROM records WHERE status = 'deduped' GROUP BY {ds_col}")
deduped_by_source = dict(cur.fetchall())

# 4. Excluded duplicates by reason
cur.execute("SELECT exclusion_reason, count(*) FROM records WHERE status = 'excluded_duplicate' GROUP BY exclusion_reason")
excluded_by_reason = dict(cur.fetchall())

# 5. Hashes populated
cur.execute("SELECT count(*) FROM records WHERE content_hash_sha256 IS NOT NULL")
hashes_count = cur.fetchone()[0]

# 6. Preference pairs check
pref_dir = Path("C:/Users/student/Krivex/data_krivex/preference_pairs/pickapic_v2")
pref_files = list(pref_dir.glob("*.json")) if pref_dir.exists() else []

sample_pref = None
if pref_files:
    with open(pref_files[0], "r", encoding="utf-8") as f:
        sample_pref = json.load(f)

# 7. Check faiss files
faiss_bin = Path("C:/Users/student/Krivex/data_krivex/manifests/faiss_index.bin")
faiss_ids = Path("C:/Users/student/Krivex/data_krivex/manifests/faiss_index.ids.json")

print(json.dumps({
    "columns": cols,
    "status_counts": status_counts,
    "source_counts": source_counts,
    "deduped_by_source": deduped_by_source,
    "excluded_by_reason": excluded_by_reason,
    "hashes_count": hashes_count,
    "total_records": sum(status_counts.values()),
    "pref_pair_files_count": len(pref_files),
    "sample_pref": {
        "id": sample_pref.get("id"),
        "pii_scrubbed": sample_pref.get("pii_scrubbed"),
        "safety_tier": sample_pref.get("safety_tier"),
        "dedup_status": sample_pref.get("dedup_status"),
        "has_image_0": bool(sample_pref.get("image_0")),
        "has_image_1": bool(sample_pref.get("image_1")),
    } if sample_pref else None,
    "faiss_bin_size_mb": round(faiss_bin.stat().st_size / (1024*1024), 2) if faiss_bin.exists() else 0,
    "faiss_ids_size_mb": round(faiss_ids.stat().st_size / (1024*1024), 2) if faiss_ids.exists() else 0,
    "db_size_gb": round(Path(db_path).stat().st_size / (1024*1024*1024), 2),
}, indent=2))
