"""Render module/banner.png shown on the module card in KernelSU Next.

Usage: python tools/make_banner.py
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "module", "banner.png")

W, H = 1280, 512
S = 2  # supersampling
FONTS = "C:/Windows/Fonts"


def font(name, size):
    return ImageFont.truetype(os.path.join(FONTS, name), size * S)


def glow(img, x, y, r, color, alpha):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse([(x - r) * S, (y - r) * S, (x + r) * S, (y + r) * S], fill=color + (alpha,))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(r * S * .55)))


def arc_points(cx, cy, r, start, end, steps=64):
    return [(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a)))
            for a in (start + (end - start) * i / steps for i in range(steps + 1))]


def stroke(d, pts, color, w):
    d.line([(x * S, y * S) for x, y in pts], fill=color, width=int(w * S), joint="curve")
    for x, y in (pts[0], pts[-1]):
        d.ellipse([(x - w / 2) * S, (y - w / 2) * S, (x + w / 2) * S, (y + w / 2) * S], fill=color)


def icon(d, kind, cx, cy, color):
    w = 4.2
    if kind == "emergency":
        for a in (90, 30, 150):
            dx, dy = 15 * math.cos(math.radians(a)), 15 * math.sin(math.radians(a))
            stroke(d, [(cx - dx, cy - dy), (cx + dx, cy + dy)], color, w)
    elif kind == "lock":
        d.rounded_rectangle([(cx - 14) * S, (cy - 3) * S, (cx + 14) * S, (cy + 17) * S], radius=4 * S, outline=color, width=int(w * S))
        stroke(d, arc_points(cx, cy - 6, 8.5, 180, 360) + [(cx + 8.5, cy - 3)], color, w)
        d.line([((cx - 8.5) * S, (cy - 6) * S), ((cx - 8.5) * S, (cy - 3) * S)], fill=color, width=int(w * S))
    elif kind == "power":
        stroke(d, arc_points(cx, cy + 2, 15, -55, 235), color, w)
        stroke(d, [(cx, cy - 18), (cx, cy - 2)], color, w)
    elif kind == "restart":
        stroke(d, arc_points(cx, cy, 15, -30, 255), color, w)
        # arrow head at the open end, pointing along the arc
        t = math.radians(-30)
        tx, ty = cx + 15 * math.cos(t), cy + 15 * math.sin(t)
        dx, dy = math.sin(t), -math.cos(t)
        nx, ny = math.cos(t), math.sin(t)
        head = [(tx + dx * 8, ty + dy * 8), (tx + nx * 7.5 - dx * 2, ty + ny * 7.5 - dy * 2),
                (tx - nx * 7.5 - dx * 2, ty - ny * 7.5 - dy * 2)]
        d.polygon([(x * S, y * S) for x, y in head], fill=color)


def main():
    img = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 255))
    glow(img, 120, 40, 330, (255, 106, 92), 95)
    glow(img, 1180, 140, 360, (92, 120, 255), 85)
    glow(img, 760, 560, 300, (170, 92, 255), 60)
    glow(img, 960, 260, 250, (31, 182, 166), 40)

    d = ImageDraw.Draw(img)

    # power menu panel
    px, py, pw, ph = 790, 46, 400, 420
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([(px + 10) * S, (py + 30) * S, (px + pw + 10) * S, (py + ph + 30) * S], 56 * S, fill=(0, 0, 0, 190))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(36 * S)))
    d.rounded_rectangle([px * S, py * S, (px + pw) * S, (py + ph) * S], 56 * S, fill=(32, 33, 36, 255))

    label_font = font("seguisb.ttf", 21)
    cells = [("emergency", "Emergency"), ("lock", "Lockdown"), ("power", "Power off"), ("restart", "Restart")]
    for n, (kind, label) in enumerate(cells):
        cx = px + 116 + (n % 2) * 168
        cy = py + 108 + (n // 2) * 186
        r = 56
        fill, fg = ((242, 139, 130), (60, 29, 26)) if kind == "emergency" else ((60, 64, 67), (232, 234, 237))
        d.ellipse([(cx - r) * S, (cy - r) * S, (cx + r) * S, (cy + r) * S], fill=fill)
        icon(d, kind, cx, cy, fg)
        d.text((cx * S, (cy + r + 26) * S), label, font=label_font, fill=(232, 234, 237), anchor="mm")

    # copy
    x = 92
    d.text((x * S, 150 * S), "POWER11", font=font("seguisb.ttf", 24), fill=(255, 130, 116), anchor="ls")
    title = font("segoeuib.ttf", 60)
    d.text((x * S, 238 * S), "Bring back the old", font=title, fill=(245, 245, 247), anchor="ls")
    d.text((x * S, 316 * S), "gem from Android 11.", font=title, fill=(245, 245, 247), anchor="ls")
    d.text((x * S, 376 * S), "For HyperOS  ·  KernelSU Next  ·  Vector", font=font("segoeui.ttf", 24), fill=(160, 160, 170), anchor="ls")

    img = img.resize((W, H), Image.LANCZOS).convert("RGB")
    img.save(OUT, optimize=True)
    print("saved", OUT, os.path.getsize(OUT) // 1024, "KB")


if __name__ == "__main__":
    main()
