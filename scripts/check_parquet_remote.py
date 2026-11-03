import os

import pyarrow.parquet as pq
import fsspec

token = os.environ.get("HF_TOKEN", "")
url = "hf://datasets/docling-project/DocLayNet-v1.1/data/test-00000-of-00002-635b47e9044a436c.parquet"
fs = fsspec.filesystem("hf", token=token)
with fs.open(url, "rb") as f:
    pf = pq.ParquetFile(f)
    print("DocLayNet schema:")
    print(pf.schema_arrow)
    print("Num rows:", pf.metadata.num_rows)
