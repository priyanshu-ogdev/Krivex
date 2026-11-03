
import json
import os
from pathlib import Path

pref_dir = Path("C:/Users/student/Krivex/data_krivex/preference_pairs/pickapic_v2")
jsons = list(pref_dir.glob("*.json"))
png_set = set(os.listdir(pref_dir))

missing_a = 0
missing_b = 0
valid_pairs = 0
corrupt_json = 0
preferred_counts = {}

for jf in jsons:
    try:
        data = json.loads(jf.read_text(encoding='utf-8'))
        img_a = data.get('image_a', '')
        img_b = data.get('image_b', '')
        pref = data.get('preferred', 'unknown')
        preferred_counts[pref] = preferred_counts.get(pref, 0) + 1
        
        if img_a not in png_set:
            missing_a += 1
        elif img_b not in png_set:
            missing_b += 1
        else:
            valid_pairs += 1
    except Exception:
        corrupt_json += 1

print(f"COMPLETE AUDIT OF ALL {len(jsons):,} PREFERENCE PAIRS:")
print(f"  Total JSON Records Verified   : {len(jsons):,}")
print(f"  Valid Pairs with Both Images  : {valid_pairs:,}")
print(f"  Missing Image A               : {missing_a}")
print(f"  Missing Image B               : {missing_b}")
print(f"  Corrupted JSONs               : {corrupt_json}")
print(f"  Preference Breakdown          : {preferred_counts}")
