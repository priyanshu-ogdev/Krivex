import sqlite3
c = sqlite3.connect(r'C:\Users\student\Krivex\data_krivex\manifests\manifest.db')
rows = c.execute('SELECT status, count(*) FROM records GROUP BY status').fetchall()
print('STATUS COUNTS:', rows)
