# /// script
# requires-python = ">=3.10"
# dependencies = ["resvg-py", "pillow"]
# ///
import io
from pathlib import Path

import resvg_py
from PIL import Image

ART = Path(__file__).resolve().parent
GAME_ICON = ART.parent / "RoguePoison" / "Media" / "icon.tga"
SIZE = 1024
GAME_SIZE = 256

png = bytes(resvg_py.svg_to_bytes(svg_path=str(ART / "icon.svg"), width=SIZE, height=SIZE))
(ART / "curseforge-icon.png").write_bytes(png)
print(f"Wrote art/curseforge-icon.png ({SIZE}x{SIZE})")

game = Image.open(io.BytesIO(png)).convert("RGBA").resize((GAME_SIZE, GAME_SIZE), Image.LANCZOS)
game.save(GAME_ICON, compression="tga_rle", orientation=1)
print(f"Wrote RoguePoison/Media/icon.tga ({GAME_SIZE}x{GAME_SIZE}, 32-bit)")
