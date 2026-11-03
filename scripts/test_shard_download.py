import os

from huggingface_hub import hf_hub_download
import time
from pathlib import Path
import pyarrow.parquet as pq
from PIL import Image
import io

token = os.environ.get("HF_TOKEN", "")

print("1. Testing download of 1 shard of creative-graphic-design/Rico...")
t0 = time.time()
f_rico = hf_hub_download(
    repo_id="creative-graphic-design/Rico",
    repo_type="dataset",
    filename="ui-screenshots-and-hierarchies-with-semantic-annotations/train-00000-of-00003.parquet",
    revision="c91e7d3c3d750ea3caae17573bd1250507966d6b",
    token=token,
)
print(f"Downloaded Rico shard in {round(time.time() - t0, 2)}s, path: {f_rico}")
table_rico = pq.read_table(f_rico)
print(f"Rico shard rows: {len(table_rico)}, schema: {table_rico.column_names}")
sample_row = table_rico.slice(0, 1).to_pydict()
img_blob = sample_row["screenshot"][0]["bytes"]
img = Image.open(io.BytesIO(img_blob))
print(f"Decoded screenshot: {img.size}, mode={img.mode}")

print("\n2. Testing download of 1 shard of DocLayNet-v1.1...")
t0 = time.time()
f_doc = hf_hub_download(
    repo_id="docling-project/DocLayNet-v1.1",
    repo_type="dataset",
    filename="data/test-00000-of-00002-635b47e9044a436c.parquet",
    revision="5e89392376049f4d589ea339ed64468310ed5c3f",
    token=token,
)
print(f"Downloaded DocLayNet shard in {round(time.time() - t0, 2)}s, path: {f_doc}")
table_doc = pq.read_table(f_doc)
print(f"DocLayNet shard rows: {len(table_doc)}, schema: {table_doc.column_names}")
sample_doc_row = table_doc.slice(0, 1).to_pydict()
img_doc_blob = sample_doc_row["image"][0]["bytes"]
img_doc = Image.open(io.BytesIO(img_doc_blob))
print(f"Decoded DocLayNet image: {img_doc.size}, mode={img_doc.mode}")

print("\nSUCCESS: Both Rico and DocLayNet download and decode flawlessly!")
