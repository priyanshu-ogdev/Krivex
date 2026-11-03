
import os
from pathlib import Path

ext = Path("C:/Users/student/Krivex/data_krivex/heldout/external_eval")
if ext.exists():
    for item in ext.iterdir():
        if item.is_dir():
            files = list(item.rglob('*'))
            f_count = sum(1 for f in files if f.is_file())
            f_size = sum(f.stat().st_size for f in files if f.is_file()) / (1024*1024)
            print(f"  Sub: {item.name:<25} | Files: {f_count:>6} | Size: {f_size:>8.2f} MB")
        else:
            print(f"  File: {item.name:<25} | Size: {item.stat().st_size / (1024*1024):>8.2f} MB")
