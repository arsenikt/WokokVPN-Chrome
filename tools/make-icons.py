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
