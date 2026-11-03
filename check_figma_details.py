
import sqlite3
from pathlib import Path

db_path = Path("C:/Users/student/Krivex/data_krivex/manifests/manifest.db")
conn = sqlite3.connect(str(db_path))
cur = conn.cursor()
cur.execute("SELECT count(*), count(distinct image_path) FROM records WHERE source_dataset = 'figma2code'")
total, distinct_imgs = cur.fetchone()
print(f"figma2code in manifest: total={total}, distinct_imgs={distinct_imgs}")

figma_dir = Path("C:/Users/student/Krivex/data_krivex/raw/figma2code")
pngs = list(figma_dir.glob('**/*.png'))
jpgs = list(figma_dir.glob('**/*.jpg'))
others = [f for f in figma_dir.glob('**/*') if f.is_file() and f.suffix not in ('.png', '.jpg')]
print(f"figma2code on disk: pngs={len(pngs)}, jpgs={len(jpgs)}, others={len(others)}")

cur.execute("SELECT image_path, count(*) as c FROM records WHERE source_dataset = 'figma2code' GROUP BY image_path HAVING c > 1 LIMIT 5")
dupes = cur.fetchall()
print("Sample duplicate image_paths in manifest for figma2code:", dupes)
