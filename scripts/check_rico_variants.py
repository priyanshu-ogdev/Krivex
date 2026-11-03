import os

from huggingface_hub import HfApi

token = os.environ.get("HF_TOKEN", "")
api = HfApi(token=token)

for repo_id in ["youngdicey/rico-raw", "ncoop57/rico_captions", "pinkmooncake/rico-screen2words", "ivelin/rico_refexp_combined"]:
    print(f"=== {repo_id} ===")
    try:
        files = api.list_repo_files(repo_id=repo_id, repo_type="dataset")
        parquets = [f for f in files if f.endswith('.parquet')]
        zips = [f for f in files if f.endswith('.zip') or f.endswith('.tar.gz')]
        print(f"Total files: {len(files)}, Parquets ({len(parquets)}): {parquets[:5]}, Archives: {zips[:5]}")
        if not parquets and not zips:
            print("Sample files:", files[:8])
    except Exception as e:
        print("Error:", e)
