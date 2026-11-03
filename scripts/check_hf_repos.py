import os

import sys
sys.stdout.reconfigure(line_buffering=True)
from huggingface_hub import HfApi

token = os.environ.get("HF_TOKEN", "")
api = HfApi(token=token)

print("=== 1. docling-project/DocLayNet ===")
try:
    files = api.list_repo_files(repo_id="docling-project/DocLayNet", repo_type="dataset")
    print("Total files:", len(files), "Sample:", files[:10])
except Exception as e:
    print("Error:", e)

print("=== Search for DocLayNet repos on HF ===")
try:
    results = list(api.list_datasets(search="DocLayNet", limit=10))
    for d in results:
        print("Dataset ID:", d.id, "downloads:", getattr(d, 'downloads', 0))
except Exception as e:
    print("Error searching DocLayNet:", e)

print("=== 2. Voxel51/rico ===")
try:
    files = api.list_repo_files(repo_id="Voxel51/rico", repo_type="dataset")
    print("Total files:", len(files), "Sample:", files[:10])
except Exception as e:
    print("Error:", e)

print("=== Search for rico / mobile UI datasets on HF ===")
try:
    results = list(api.list_datasets(search="rico", limit=10))
    for d in results:
        print("Dataset ID:", d.id, "downloads:", getattr(d, 'downloads', 0))
except Exception as e:
    print("Error searching rico:", e)

print("=== 3. liuhuohuo2/pick-a-pic-v2 ===")
try:
    files = api.list_repo_files(repo_id="liuhuohuo2/pick-a-pic-v2", repo_type="dataset")
    parquets = [f for f in files if f.endswith('.parquet')]
    print("Total parquets:", len(parquets), "Sample:", parquets[:8])
except Exception as e:
    print("Error:", e)
