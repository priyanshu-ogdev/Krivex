import psutil
try:
    p = psutil.Process(6280)
    print("PID 6280:", p.name(), "Status:", p.status())
    print("Memory:", f"{p.memory_info().rss / (1024**2):.1f} MB")
    print("CPU %:", p.cpu_percent(interval=1.0))
except Exception as e:
    print("Process finished or Error:", e)
