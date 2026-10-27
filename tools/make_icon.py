"""Render assets/icon.png shown on modules.kernelsu.org.

Usage: python tools/make_icon.py
"""
import os

from PIL import Image, ImageDraw

from make_banner import ROOT, S, glow, icon

OUT = os.path.join(ROOT, "assets", "icon.png")
W = H = 512


def main():
    img = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 255))
    glow(img, 40, 30, 260, (255, 106, 92), 95)
    glow(img, 500, 480, 280, (92, 120, 255), 85)

    d = ImageDraw.Draw(img)
    cells = ["emergency", "lock", "power", "restart"]
    for n, kind in enumerate(cells):
        cx = 166 + (n % 2) * 180
        cy = 166 + (n // 2) * 180
        r = 72
        fill, fg = ((242, 139, 130), (60, 29, 26)) if kind == "emergency" else ((60, 64, 67), (232, 234, 237))
        d.ellipse([(cx - r) * S, (cy - r) * S, (cx + r) * S, (cy + r) * S], fill=fill)
        # icons are drawn at banner size; scale them up via a temporary layer
        layer = Image.new("RGBA", (120 * S, 120 * S), (0, 0, 0, 0))
        icon(ImageDraw.Draw(layer), kind, 60, 60, fg)
        layer = layer.resize((156 * S, 156 * S), Image.LANCZOS)
        img.alpha_composite(layer, ((cx - 78) * S, (cy - 78) * S))

    img = img.resize((W, H), Image.LANCZOS).convert("RGB")
    img.save(OUT, optimize=True)
    print("saved", OUT, os.path.getsize(OUT) // 1024, "KB")


if __name__ == "__main__":
    main()
