
import json
from pathlib import Path

pref_dir = Path("C:/Users/student/Krivex/data_krivex/preference_pairs/pickapic_v2")
jsons = list(pref_dir.glob("*.json"))
pngs = set(p.name for p in pref_dir.glob("*.png"))

missing_png = 0
valid_pairs = 0
corrupt_json = 0

for jf in jsons[:2000]: # check 2000 samples
    try:
        data = json.loads(jf.read_text(encoding='utf-8'))
        w_img = Path(data.get('winner_image', '')).name
        l_img = Path(data.get('loser_image', '')).name
        if w_img not in pngs or l_img not in pngs:
            missing_png += 1
        else:
            valid_pairs += 1
    except Exception:
        corrupt_json += 1

print(f"Sample Check of 2000 Preference Pairs:")
print(f"  Valid Pairs with Both Images: {valid_pairs}")
print(f"  Missing Winner/Loser Images:  {missing_png}")
print(f"  Corrupt JSONs:               {corrupt_json}")
