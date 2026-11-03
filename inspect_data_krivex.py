
import os
from pathlib import Path

root = Path("C:/Users/student/Krivex/data_krivex")

print("=== DATA_KRIVEX DIRECTORY STRUCTURE & FILE STATS ===")
for item in root.iterdir():
    if item.is_dir():
        # count files and total size
        all_files = list(item.rglob("*"))
        file_count = sum(1 for f in all_files if f.is_file())
        total_size = sum(f.stat().st_size for f in all_files if f.is_file()) / (1024*1024)
        print(f"Directory: {item.name:<25} | Files: {file_count:>8,} | Size: {total_size:>10,.2f} MB")
        
        # Subdirectories for raw, preference_pairs, etc.
        if item.name in ("raw", "preference_pairs", "processed", "eval", "eval_external"):
            for sub in item.iterdir():
                if sub.is_dir():
                    sub_files = list(sub.rglob("*"))
                    sub_count = sum(1 for f in sub_files if f.is_file())
                    sub_size = sum(f.stat().st_size for f in sub_files if f.is_file()) / (1024*1024)
                    print(f"    Sub: {sub.name:<21} | Files: {sub_count:>8,} | Size: {sub_size:>10,.2f} MB")
    else:
        print(f"File: {item.name:<30} | Size: {item.stat().st_size / (1024*1024):>10,.2f} MB")
