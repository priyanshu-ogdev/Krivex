import os

import pyarrow.parquet as pq
import fsspec

token = os.environ.get("HF_TOKEN", "")
url = "hf://datasets/pinkmooncake/rico-screen2words/data/train-00000-of-00004-b27f401191db6a34.parquet"
fs = fsspec.filesystem("hf", token=token)
with fs.open(url, "rb") as f:
    pf = pq.ParquetFile(f)
    print("screen2words schema:")
    print(pf.schema_arrow)
    print("Num rows:", pf.metadata.num_rows)
