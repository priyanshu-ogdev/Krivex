import os

from huggingface_hub import HfApi

token = os.environ.get("HF_TOKEN", "")
api = HfApi(token=token)

for repo_id in ["docling-project/DocLayNet-v1.1", "creative-graphic-design/Rico", "liuhuohuo2/pick-a-pic-v2"]:
    info = api.dataset_info(repo_id=repo_id)
    print(f"{repo_id} sha: {info.sha}")
