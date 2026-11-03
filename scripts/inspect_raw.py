
with open(r"C:\Users\student\Krivex\logs\data-forge\run_20261102_223759.log", "rb") as f:
    chunk = f.read(1000)
    print("Raw bytes repr:", repr(chunk[:200]))
    try:
        print("UTF-8 decoded:\n", chunk[:500].decode("utf-8"))
    except Exception as e:
        print("UTF-8 decode error:", e)
        print("UTF-16LE decoded:\n", chunk[:500].decode("utf-16le", errors="replace"))
