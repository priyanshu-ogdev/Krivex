import sqlite3
conn = sqlite3.connect('C:/Users/student/Krivex/data_krivex/manifests/manifest.db')
cur = conn.cursor()
cur.execute('SELECT status, count(*) FROM records GROUP BY status')
print('Current manifest counts:', cur.fetchall())
conn.close()
