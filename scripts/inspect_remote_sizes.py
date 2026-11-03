import os

from huggingface_hub import HfApi
import pyarrow.parquet as pq
import fsspec

token = os.environ.get("HF_TOKEN", "")
api = HfApi(token=token)

repo_id = "docling-project/DocLayNet-v1.1"
info = api.get_paths_info(repo_id=repo_id, repo_type="dataset", paths=["data/test-00000-of-00002-635b47e9044a436c.parquet"])
for i in info:
    print(f"File: {i.path}, Size: {round(i.size / (1024*1024), 2)} MB")

# Also check Voxel51/rico file size
rico_info = api.get_paths_info(repo_id="Voxel51/rico", repo_type="dataset", paths=["data/data_0/10015.jpg"])
for i in rico_info:
    print(f"File: {i.path}, Size: {round(i.size / 1024, 2)} KB")
