# Cuts the 3D glass icon out of assets/gemini/logo.png onto a transparent background
# and writes all extension / site / README icon sizes.  Usage: python tools/make-icons.py
import pathlib
from PIL import Image, ImageDraw, ImageEnhance
root = pathlib.Path(__file__).resolve().parent.parent
BOX, RAD = (185, 185, 839, 839), 116  # rounded tile inside the 1024px source

im = Image.open(root / "assets/gemini/logo.png").convert("RGBA").crop(BOX)
w, h = im.size; k = 4
mask = Image.new("L", (w * k, h * k), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, w * k - 1, h * k - 1), RAD * k, fill=255)
im.putalpha(mask.resize((w, h), Image.LANCZOS))
on = im.resize((1024, 1024), Image.LANCZOS)
off = ImageEnhance.Brightness(ImageEnhance.Color(on).enhance(0)).enhance(0.75)
off.putalpha(on.getchannel("A"))

on.save(root / "assets/icon/on-1024.png", optimize=True)
on.resize((512, 512), Image.LANCZOS).save(root / "docs/img/logo.png", optimize=True)
for name, src in (("on", on), ("off", off)):
    for s in (16, 32, 48, 128):
        src.resize((s, s), Image.LANCZOS).save(root / f"extension/icons/{name}{s}.png", optimize=True)

# Site hero emblem: drop the dark glass tile, keep only what glows ("unscreen" against the tile colour).
import numpy as np
src = np.asarray(Image.open(root / "assets/gemini/logo.png").convert("RGB").crop((200, 200, 824, 824)), dtype=np.float32)
base = np.array([46, 48, 54], np.float32)            # tile colour
lift = np.clip(src - base, 0, None) / (255 - base)   # 0..1 above the tile
a = lift.max(axis=2, keepdims=True)
a = np.clip((a - 0.10) / 0.90, 0, 1) ** 0.85         # kill tile noise / glass sheen
n = a.shape[0]; yy, xx = np.mgrid[0:n, 0:n] / (n - 1) - 0.5
a = a * np.clip((0.49 - np.hypot(xx, yy * 1.05)) / 0.12, 0, 1)[..., None]  # fade tile edges
rgb = np.where(a > 0, np.clip(lift / np.maximum(a, 1e-3), 0, 1), 0) * 255
glow = Image.fromarray(np.concatenate([rgb, a * 255], axis=2).astype(np.uint8), "RGBA")
glow.resize((512, 512), Image.LANCZOS).save(root / "docs/img/logo-glow.png", optimize=True)
