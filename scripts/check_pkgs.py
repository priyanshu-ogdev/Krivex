
import importlib.util

packages = ['torch', 'torchvision', 'torchaudio', 'transformers', 'diffusers', 'accelerate', 'vllm', 'sglang', 'ollama', 'fastapi', 'uvicorn', 'openai', 'httpx', 'triton', 'mediapipe', 'faiss']
for p in packages:
    spec = importlib.util.find_spec(p)
    if spec is not None:
        try:
            mod = __import__(p)
            ver = getattr(mod, '__version__', 'installed')
            print(f"{p}: {ver}")
        except Exception as e:
            print(f"{p}: installed (import error: {e})")
    else:
        print(f"{p}: NOT INSTALLED")
