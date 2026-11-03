
import pyarrow.parquet as pq
from pathlib import Path

raw_dir = Path(r"C:\Users\student\Krivex\data_krivex\raw")

for ds in ["crello", "pku_poster", "abo_ecommerce"]:
    p = raw_dir / ds / "_parquet"
    files = list(p.rglob("*.parquet"))
    if not files:
        continue
    pf = pq.ParquetFile(str(files[0]))
    batch = next(pf.iter_batches(batch_size=1))
    row = batch.to_pylist()[0]
    print(f"\n[{ds}] Row keys: {list(row.keys())}")
    for k, v in row.items():
        if isinstance(v, (bytes, bytearray)):
            print(f"  {k}: bytes (len={len(v)})")
        elif isinstance(v, dict):
            print(f"  {k}: dict keys={list(v.keys())}")
        elif isinstance(v, list) and v and isinstance(v[0], dict):
            print(f"  {k}: list of dicts (len={len(v)}), first dict keys={list(v[0].keys())}")
        else:
            print(f"  {k}: {repr(v)[:60]}")
