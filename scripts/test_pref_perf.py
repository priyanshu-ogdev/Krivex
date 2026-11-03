
import time
from pathlib import Path
from data_forge.utils.pii_faces import load_face_detector, blur_faces
from PIL import Image

detector = load_face_detector(min_confidence=0.5)
print("Detector loaded:", detector is not None)

pref_p = Path("data_krivex/preference_pairs/pickapic_v2")
pairs = list(pref_p.glob("*.json"))[:20]
print(f"Testing on {len(pairs)} pairs...")

t0 = time.time()
faces_found = 0
for p in pairs:
    import json
    meta = json.loads(p.read_text(encoding="utf-8"))
    img_a = Image.open(pref_p / meta["image_a"])
    img_b = Image.open(pref_p / meta["image_b"])
    res_a, mod_a, det_a = blur_faces(img_a, detector)
    res_b, mod_b, det_b = blur_faces(img_b, detector)
    if mod_a or mod_b:
        faces_found += 1

elapsed = time.time() - t0
print(f"Processed {len(pairs)*2} images in {elapsed:.2f}s ({(len(pairs)*2)/elapsed:.1f} img/s on single thread). Faces found: {faces_found}")
