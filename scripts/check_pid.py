import psutil
try:
    p = psutil.Process(16832)
    print("PID:", p.pid, p.name(), p.status(), p.cmdline())
    for c in p.children(recursive=True):
        print("  CHILD:", c.pid, c.name(), c.status(), c.cmdline())
except Exception as e:
    print("Error:", e)
