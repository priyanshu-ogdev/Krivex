
import json

with open('C:/Users/student/Krivex/logs/data-forge/run_20261102_223503.log', 'r', encoding='utf-8', errors='ignore') as f:
    for line in f:
        try:
            d = json.loads(line)
            ev = d.get('event', '')
            if any(k in ev for k in ['dataset', 'fetch', 'complete', 'summary', 'error', 'write']):
                print(f"{ev}: {d.get('dataset')} | count={d.get('count') or d.get('records') or d.get('written')} | error={d.get('error')}")
        except Exception:
            pass
