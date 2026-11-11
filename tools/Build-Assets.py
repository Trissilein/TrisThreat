"""Builds the TrisThreat textures into Assets/ (reproducible, needs: pip install pillow).

Capsule_Fill.tga    128x64 white pill, tinted in game (bar fill and dark background)
Capsule_Border.tga  128x64 gold-ready ring (white, tinted in game), transparent centre
TrisThreatIcon.tga  64x64 addon icon (dark badge, gold ring, red and green capsule)
PNG copies go to docs/branding/. 32-bit uncompressed top-left TGA like WoWraVox's assets.
"""
import os
import struct

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SS = 4  # supersampling for smooth edges


def write_tga(path, img):
    img = img.convert("RGBA")
    w, h = img.size
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8 | 0x20)
    px = img.load()
    data = bytearray()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            data += bytes((b, g, r, a))
    with open(path, "wb") as fh:
        fh.write(header + bytes(data))


def pill(w, h, inset=0, outline=None):
    big = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    box = (inset * SS, inset * SS, (w - inset) * SS - 1, (h - inset) * SS - 1)
    radius = (box[3] - box[1]) // 2
    if outline:
        d.rounded_rectangle(box, radius=radius, fill=(255, 255, 255, 255))
        inner = tuple(v + (outline * SS if i < 2 else -outline * SS) for i, v in enumerate(box))
        inner_r = max(1, (inner[3] - inner[1]) // 2)
        cut = Image.new("L", big.size, 0)
        ImageDraw.Draw(cut).rounded_rectangle(inner, radius=inner_r, fill=255)
        alpha = big.getchannel("A")
        alpha = Image.composite(Image.new("L", big.size, 0), alpha, cut)
        big.putalpha(alpha)
    else:
        d.rounded_rectangle(box, radius=radius, fill=(255, 255, 255, 255))
    return big.resize((w, h), Image.LANCZOS)


def icon():
    size = 64
    big = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    s = SS
    d.ellipse((2 * s, 2 * s, 62 * s, 62 * s), fill=(224, 173, 61, 255))
    d.ellipse((5 * s, 5 * s, 59 * s, 59 * s), fill=(14, 16, 20, 255))
    d.rounded_rectangle((12 * s, 14 * s, 52 * s, 30 * s), radius=8 * s, fill=(217, 38, 38, 255))
    d.rounded_rectangle((12 * s, 34 * s, 36 * s, 50 * s), radius=8 * s, fill=(51, 217, 77, 255))
    d.rounded_rectangle((38 * s, 34 * s, 52 * s, 50 * s), radius=7 * s, fill=(64, 140, 255, 255))
    return big.resize((size, size), Image.LANCZOS)


def main():
    assets = os.path.join(ROOT, "Assets")
    branding = os.path.join(ROOT, "docs", "branding")
    os.makedirs(assets, exist_ok=True)
    os.makedirs(branding, exist_ok=True)
    items = {
        "Capsule_Fill": pill(128, 64),
        "Capsule_Border": pill(128, 64, outline=3),
        "TrisThreatIcon": icon(),
    }
    for name, img in items.items():
        write_tga(os.path.join(assets, name + ".tga"), img)
        img.save(os.path.join(branding, name + ".png"))
        print("wrote", name)


if __name__ == "__main__":
    main()
