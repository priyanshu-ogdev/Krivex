
import pyarrow.parquet as pq
from pathlib import Path

raw_dir = Path(r"C:\Users\student\Krivex\data_krivex\raw")
for ds in ["pku_poster", "abo_ecommerce"]:
    p = raw_dir / ds / "_parquet"
    files = list(p.rglob("*.parquet"))
    if files:
        pf = pq.ParquetFile(str(files[0]))
        print(f"\n[{ds}] Schema ({len(files)} files):")
        print(" ", pf.schema.names[:10])
