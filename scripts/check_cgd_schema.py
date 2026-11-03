import os

import pyarrow.parquet as pq
import fsspec

token = os.environ.get("HF_TOKEN", "")
url = "hf://datasets/creative-graphic-design/Rico/ui-screenshots-and-hierarchies-with-semantic-annotations/train-00000-of-00003.parquet"
fs = fsspec.filesystem("hf", token=token)
with fs.open(url, "rb") as f:
    pf = pq.ParquetFile(f)
    print("creative-graphic-design/Rico schema:")
    print(pf.schema_arrow)
    print("Num rows in shard 0:", pf.metadata.num_rows)
