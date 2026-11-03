
import asyncio
import os
from pathlib import Path
import sys
sys.path.insert(0, "C:/Users/student/Krivex/data-forge/src")
from data_forge.config import PipelineConfig, DatasetSpec, PathsConfig
from data_forge.data.fetcher import DatasetFetcher

config = PipelineConfig(
    data_root=Path("C:/Users/student/Krivex/data_krivex"),
    paths=PathsConfig(),
)
config.resolved_paths = {
    "raw": config.data_root / "raw",
    "preference_pairs": config.data_root / "preference_pairs",
}

token = os.environ.get("HF_TOKEN", "")
os.environ["HF_TOKEN"] = token
fetcher = DatasetFetcher(config)

async def test():
    # 1. Test Rico
    print("Testing Rico fetcher (limit 3)...")
    spec_rico = DatasetSpec(
        display_name="Rico Test",
        source_type="huggingface",
        category="mobile_ui",
        repo_id="creative-graphic-design/Rico",
        revision="c91e7d3c3d750ea3caae17573bd1250507966d6b",
        fetch_config={
            "download_mode": "hf_parquet_images",
            "config_subfolder": "ui-screenshots-and-hierarchies-with-semantic-annotations",
            "image_column": "screenshot",
            "sample_size": 3,
        }
    )
    dest_rico = config.data_root / "raw" / "rico_semantic_test"
    recs_rico = await fetcher._fetch_hf_parquet_images("rico_semantic_test", spec_rico, dest_rico)
    print(f"Rico fetched {len(recs_rico)} records:")
    if recs_rico:
        print(recs_rico[0])

    # 2. Test DocLayNet
    print("\nTesting DocLayNet fetcher (limit 3)...")
    spec_doc = DatasetSpec(
        display_name="DocLayNet Test",
        source_type="huggingface",
        category="editorial_document",
        repo_id="docling-project/DocLayNet-v1.1",
        revision="5e89392376049f4d589ea339ed64468310ed5c3f",
        fetch_config={
            "download_mode": "hf_parquet_images",
            "file_patterns": ["data/test-*.parquet"],
            "image_column": "image",
            "sample_size": 3,
        }
    )
    dest_doc = config.data_root / "raw" / "doclaynet_test"
    recs_doc = await fetcher._fetch_hf_parquet_images("doclaynet_test", spec_doc, dest_doc)
    print(f"DocLayNet fetched {len(recs_doc)} records:")
    if recs_doc:
        print(recs_doc[0])

asyncio.run(test())
