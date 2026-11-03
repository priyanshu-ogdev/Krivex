
import json
from pathlib import Path

pref_dir = Path("C:/Users/student/Krivex/data_krivex/preference_pairs/pickapic_v2")
jsons = list(pref_dir.glob("*.json"))
if jsons:
    sample_json = jsons[0]
    print("JSON file name:", sample_json.name)
    print("JSON content:")
    print(sample_json.read_text(encoding='utf-8'))
    
    pngs = list(pref_dir.glob("*.png"))[:5]
    print("Sample PNG file names:")
    for p in pngs:
        print(" ", p.name)
