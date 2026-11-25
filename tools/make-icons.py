# Renders assets/icon/{on,off}.svg -> transparent PNGs (headless Chrome + Pillow).
# Usage: python tools/make-icons.py
import os, subprocess, tempfile, shutil, pathlib
from PIL import Image
root = pathlib.Path(__file__).resolve().parent.parent
chrome = os.environ.get("CHROME") or next(p for p in [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/usr/bin/google-chrome"] if os.path.exists(p))
tmp = pathlib.Path(tempfile.mkdtemp())
for v in ("on", "off"):
    big = tmp / f"{v}.png"
    subprocess.run([chrome, "--headless=new", f"--user-data-dir={tmp/'prof'}", "--disable-gpu",
        "--hide-scrollbars", "--default-background-color=00000000", "--force-device-scale-factor=8",
        "--window-size=128,128", f"--screenshot={big}", (root/"assets/icon"/f"{v}.svg").as_uri()],
        check=True, capture_output=True)
    im = Image.open(big).convert("RGBA")
    for s in (16, 32, 48, 128):
        im.resize((s, s), Image.LANCZOS).save(root/f"extension/icons/{v}{s}.png", optimize=True)
    if v == "on":
        im.resize((512, 512), Image.LANCZOS).save(root/"docs/img/logo.png", optimize=True)
        im.save(root/"assets/icon/on-1024.png", optimize=True)
shutil.rmtree(tmp, ignore_errors=True)
