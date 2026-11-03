import os

import pyarrow.parquet as pq
import fsspec

token = os.environ.get("HF_TOKEN", "")
url = "hf://datasets/youngdicey/rico-raw/data/train-00000-of-00015-6fa2d6da502fcbc2.parquet"
fs = fsspec.filesystem("hf", token=token)
with fs.open(url, "rb") as f:
    pf = pq.ParquetFile(f)
    print("rico-raw schema:")
    print(pf.schema_arrow)
    print("Num rows:", pf.metadata.num_rows)
