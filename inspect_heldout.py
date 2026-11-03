
import os
from pathlib import Path

heldout = Path("C:/Users/student/Krivex/data_krivex/heldout")
if heldout.exists():
    items = list(heldout.iterdir())
    print(f"Total items in heldout: {len(items)}")
    for item in items[:20]:
        if item.is_dir():
            count = len(list(item.glob('*')))
            print(f"  Dir: {item.name:<30} ({count} items)")
        else:
            print(f"  File: {item.name:<30} ({item.stat().st_size / (1024*1024):.2f} MB)")
else:
    print("heldout does not exist")
