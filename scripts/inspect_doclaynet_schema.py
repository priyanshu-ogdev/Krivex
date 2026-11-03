import os

import pandas as pd
from huggingface_hub import hf_hub_download

token = os.environ.get("HF_TOKEN", "")
f = hf_hub_download(repo_id="docling-project/DocLayNet-v1.1", repo_type="dataset", filename="data/test-00000-of-00002-635b47e9044a436c.parquet", token=token)
df = pd.read_parquet(f)
print("DocLayNet-v1.1 columns:", list(df.columns))
print("Sample row keys/types:", {col: type(df[col].iloc[0]).__name__ for col in df.columns})
print("Total rows in test shard 0:", len(df))
