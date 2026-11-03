
import sqlite3
from pathlib import Path

db_path = Path("C:/Users/student/Krivex/data_krivex/manifests/manifest.db")
conn = sqlite3.connect(str(db_path))
cur = conn.cursor()

sources = ['abo_ecommerce', 'crello', 'doclaynet', 'figma2code', 'pku_poster', 'rico_semantic']
print(f"{'Source':<20} | {'Total Records':<14} | {'Distinct ImgPaths':<18} | {'On-Disk Images':<15} | {'Mismatch'}")
print("-" * 80)

raw_root = Path("C:/Users/student/Krivex/data_krivex/raw")

for s in sources:
    cur.execute("SELECT count(*), count(distinct image_path) FROM records WHERE source_dataset = ?", (s,))
    tot, dist = cur.fetchone()
    
    s_dir = raw_root / s
    # count png and jpg
    img_count = len(list(s_dir.glob('**/*.png'))) + len(list(s_dir.glob('**/*.jpg')))
    mismatch = "YES" if dist != img_count else "NO"
    print(f"{s:<20} | {tot:>14,} | {dist:>18,} | {img_count:>15,} | {mismatch}")

conn.close()
