
import pyarrow.parquet as pq
from pathlib import Path

pq_dir = Path(r"C:\Users\student\Krivex\data_krivex\raw\crello\_parquet")
files = list(pq_dir.rglob("*.parquet"))
print(f"Found {len(files)} parquet files in crello")
if files:
    pf = pq.ParquetFile(str(files[0]))
    print(f"Schema: {pf.schema.names}")
    table = pf.read_row_group(0, columns=pf.schema.names[:5])
    row = table.slice(0, 1).to_pydict()
    for k, v in row.items():
        val = v[0]
        val_repr = repr(val)[:120]
        print(f"  {k}: type={type(val).__name__}, val={val_repr}")
