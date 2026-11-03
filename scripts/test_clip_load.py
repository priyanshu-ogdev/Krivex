
import time
import torch
from transformers import CLIPModel, CLIPProcessor

print("Testing CLIP loading on RTX 6000 Ada...")
start = time.time()
model_id = "openai/clip-vit-large-patch14-336"
rev = "ce19dc912ca5cd21c8a653c79e251e808ccabcd1"

processor = CLIPProcessor.from_pretrained(model_id, revision=rev)
model = CLIPModel.from_pretrained(model_id, revision=rev, torch_dtype=torch.float16).to("cuda")
model.eval()

vram_used = torch.cuda.memory_allocated() / (1024**3)
print(f"[OK] CLIP loaded in {time.time() - start:.2f}s! VRAM allocated: {vram_used:.2f} GB")

# Quick dummy inference test
dummy_img = torch.randn(1, 3, 336, 336, dtype=torch.float16, device="cuda")
with torch.no_grad():
    vision_out = model.vision_model(pixel_values=dummy_img)
    embeds = model.visual_projection(vision_out[1])
    embeds = embeds / embeds.norm(p=2, dim=-1, keepdim=True)
print(f"[OK] Inference test succeeded! Embedding shape: {embeds.shape}, dtype: {embeds.dtype}")
