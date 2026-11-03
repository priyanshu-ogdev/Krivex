
from pathlib import Path
from data_forge.data.parquet_reader import iter_parquet_rows

raw_dir = Path(r"C:\Users\student\Krivex\data_krivex\raw")
for ds in ["abo_ecommerce", "pku_poster", "crello"]:
    p = raw_dir / ds / "_parquet"
    files = list(p.rglob("*.parquet"))
    if files:
        for row in iter_parquet_rows([files[0]], batch_size=1, limit=1):
            print(f"\n[{ds}] Row keys: {list(row.keys())}")
            for k, v in list(row.items())[:5]:
                print(f"   {k}: type={type(v).__name__}, len={len(v) if isinstance(v, (bytes, str, list, dict)) else v}")
            break
