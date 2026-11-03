import os

import asyncio
import sys
from pathlib import Path
from PIL import Image
import pyarrow.parquet as pq
import fsspec

token = os.environ.get("HF_TOKEN", "")
fs = fsspec.filesystem("hf", token=token)

print("--- 1. Testing creative-graphic-design/Rico ---")
try:
    url = "hf://datasets/creative-graphic-design/Rico/ui-screenshots-and-hierarchies-with-semantic-annotations/train-00000-of-00003.parquet"
    with fs.open(url, "rb") as f:
        table = pq.read_table(f)
        df_rico = table.slice(0, 3).to_pandas()
        print("Rico slice successful, columns:", list(df_rico.columns))
        img_dict = df_rico["screenshot"].iloc[0]
        import io
        img = Image.open(io.BytesIO(img_dict["bytes"]))
        print("Decoded Rico screenshot size:", img.size, img.format)
except Exception as e:
    print("Rico test error:", e)

print("\n--- 2. Testing docling-project/DocLayNet-v1.1 ---")
try:
    url = "hf://datasets/docling-project/DocLayNet-v1.1/data/test-00000-of-00002-635b47e9044a436c.parquet"
    with fs.open(url, "rb") as f:
        table = pq.read_table(f)
        df_doc = table.slice(0, 3).to_pandas()
        print("DocLayNet slice successful, columns:", list(df_doc.columns))
        img_dict = df_doc["image"].iloc[0]
        import io
        img = Image.open(io.BytesIO(img_dict["bytes"]))
        print("Decoded DocLayNet image size:", img.size, img.format)
except Exception as e:
    print("DocLayNet test error:", e)

print("\n--- 3. Testing liuhuohuo2/pick-a-pic-v2 ---")
try:
    url = "hf://datasets/liuhuohuo2/pick-a-pic-v2/data/test-00000-of-00014-387db523fa7e7121.parquet"
    with fs.open(url, "rb") as f:
        table = pq.read_table(f)
        df_pick = table.slice(0, 3).to_pandas()
        print("Pick-a-Pic slice successful, columns:", list(df_pick.columns))
        import io
        img0 = Image.open(io.BytesIO(df_pick["jpg_0"].iloc[0]))
        img1 = Image.open(io.BytesIO(df_pick["jpg_1"].iloc[0]))
        label = df_pick["label_0"].iloc[0]
        print(f"Decoded Pick-a-Pic pair: img0={img0.size}, img1={img1.size}, label={label}")
except Exception as e:
    print("Pick-a-Pic test error:", e)

print("\nAll 3 data format validations passed!")
