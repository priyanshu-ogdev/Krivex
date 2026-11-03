
import sqlite3
import os

db_path = r"C:\Users\student\Krivex\data_krivex\manifests\manifest.db"
if os.path.exists(db_path):
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("SELECT count(*) FROM records")
    print(f"Total manifest records: {cur.fetchone()[0]}")
    cur.execute("SELECT source_dataset, count(*) FROM records GROUP BY source_dataset")
    for row in cur.fetchall():
        print(f"  - {row[0]}: {row[1]}")
    conn.close()
else:
    print("manifest.db not found")
