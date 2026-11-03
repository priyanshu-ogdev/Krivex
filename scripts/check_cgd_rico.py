import os

from huggingface_hub import HfApi

token = os.environ.get("HF_TOKEN", "")
api = HfApi(token=token)

try:
    files = api.list_repo_files(repo_id="creative-graphic-design/Rico", repo_type="dataset")
    parquets = [f for f in files if f.endswith('.parquet')]
    print("creative-graphic-design/Rico total files:", len(files), "parquets:", len(parquets))
    print("Sample parquets:", parquets[:10])
except Exception as e:
    print("Error:", e)
