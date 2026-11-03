
import sqlite3
from pathlib import Path

db_path = Path("C:/Users/student/Krivex/data_krivex/manifests/manifest.db")
conn = sqlite3.connect(str(db_path))
cur = conn.cursor()
cur.execute("SELECT count(*), count(distinct image_path) FROM records WHERE source_dataset = 'pku_poster'")
total, distinct_imgs = cur.fetchone()
print(f"pku_poster in manifest: total={total}, distinct_imgs={distinct_imgs}")

pku_dir = Path("C:/Users/student/Krivex/data_krivex/raw/pku_poster")
pngs = list(pku_dir.glob('**/*.png'))
jpgs = list(pku_dir.glob('**/*.jpg'))
others = [f for f in pku_dir.glob('**/*') if f.is_file() and f.suffix not in ('.png', '.jpg')]
print(f"pku_poster on disk: pngs={len(pngs)}, jpgs={len(jpgs)}, others={len(others)}")
