
import json

def read_lines(filepath):
    with open(filepath, "rb") as f:
        data = f.read()
    if data.startswith(b"\xff\xfe") or data.startswith(b"\xfe\xff"):
        text = data.decode("utf-16", errors="replace")
    elif data.startswith(b"\xef\xbb\xbf"):
        text = data.decode("utf-8-sig", errors="replace")
    else:
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            text = data.decode("utf-16le", errors="replace")
    return text.splitlines()

for log_name in ["run_20261102_223503.log", "run_20261102_223759.log"]:
    print("=" * 30, log_name, "=" * 30)
    lines = read_lines(f"C:/Users/student/Krivex/logs/data-forge/{log_name}")
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            data = json.loads(line)
            ev = data.get("event", "")
            lvl = data.get("level", "")
            if any(x in ev for x in ["dataset", "fetch", "complete", "summary", "error", "warning", "fail", "stage"]) or lvl in ("error", "warning"):
                ds = data.get("dataset", "")
                msg = data.get("error") or data.get("reason") or data.get("records") or data.get("note") or ""
                print(f"[{lvl.upper()}] {ev} | ds={ds} | {msg} | stage={data.get('stage')}")
        except Exception:
            pass
