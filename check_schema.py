
import sqlite3
from pathlib import Path

db_path = Path("C:/Users/student/Krivex/data_krivex/manifests/manifest.db")
conn = sqlite3.connect(str(db_path))
cur = conn.cursor()
cur.execute("PRAGMA table_info(records)")
columns = [row[1] for row in cur.fetchall()]
print("COLUMNS IN records:", columns)
conn.close()
