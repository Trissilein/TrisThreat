"""Builds the TrisThreat textures into Assets/ (reproducible, needs: pip install pillow).

Tab_Fill.tga        128x48 white tab (rounded top corners, flat bottom), tinted in game with the bar color
Tab_Border.tga      128x48 open-bottom outline of the tab (white, tinted black in game)
TrisThreatIcon.tga  128x128 addon icon (threat gauge badge: gold bevel, green-to-red arc, needle, 70% capsule)
PNG copies go to docs/branding/. 32-bit uncompressed top-left TGA like WoWraVox's assets.
"""
import math
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


def tab(w, h, outline=None, radius=18):
    """Tab that grows out of a bar: rounded top corners, flat bottom. outline: open-bottom ring only."""
    big = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    r = radius * SS
    shape = Image.new("L", big.size, 0)
    ImageDraw.Draw(shape).rounded_rectangle((0, 0, w * SS - 1, h * SS * 2), radius=r, fill=255)
    if outline:
        o = outline * SS
        cut = Image.new("L", big.size, 0)
        ImageDraw.Draw(cut).rounded_rectangle((o, o, w * SS - 1 - o, h * SS * 3), radius=max(1, r - o), fill=255)
        shape = Image.composite(Image.new("L", big.size, 0), shape, cut)
    big.paste((255, 255, 255, 255), mask=shape)
    return big.resize((w, h), Image.LANCZOS)


def lerp(c1, c2, t):
    return tuple(int(round(c1[i] + (c2[i] - c1[i]) * t)) for i in range(3))


def gauge_color(t):
    """Green -> yellow -> orange -> red along the gauge (t 0..1)."""
    stops = [(0.0, (46, 204, 92)), (0.4, (238, 214, 64)), (0.7, (244, 140, 34)), (1.0, (222, 40, 40))]
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            return lerp(c0, c1, (t - t0) / (t1 - t0))
    return stops[-1][1]


def icon():
    """Threat gauge badge: gold bevel ring, dark disc, green-to-red arc, needle, hub and a percent capsule."""
    size = 128
    s = SS * 2
    N = size * s
    big = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    c = N / 2

    def circle(r, fill):
        d.ellipse((c - r * s, c - r * s, c + r * s, c + r * s), fill=fill)

    # gold bevel: concentric rings from bright to dark
    for i in range(24):
        r = 62 - i * 0.25
        circle(r, lerp((250, 220, 120), (150, 105, 28), i / 23) + (255,))
    # dark disc with a soft radial falloff
    for i in range(40):
        r = 55.5 - i * 0.7
        circle(r, lerp((34, 42, 58), (8, 10, 15), i / 39) + (255,))
    # thin inner gold line
    d.ellipse((c - 52 * s, c - 52 * s, c + 52 * s, c + 52 * s), outline=(196, 152, 52, 255), width=int(1.2 * s))

    cx, cy, rad = c, c + 8 * s, 36 * s
    # gauge track
    d.arc((cx - rad, cy - rad, cx + rad, cy + rad), 180, 360, fill=(18, 22, 30, 255), width=int(13 * s))
    # colored arc in small steps
    steps = 90
    for i in range(steps):
        t0, t1 = i / steps, (i + 1) / steps
        d.arc((cx - rad, cy - rad, cx + rad, cy + rad), 180 + 180 * t0 - 0.4, 180 + 180 * t1 + 0.4,
              fill=gauge_color((t0 + t1) / 2) + (255,), width=int(9 * s))
    # ticks
    for k in range(0, 11):
        ang = math.radians(180 + 18 * k)
        r1, r2 = rad + 8 * s, rad + (11 if k % 5 == 0 else 9.5) * s
        d.line((cx + r1 * math.cos(ang), cy + r1 * math.sin(ang), cx + r2 * math.cos(ang), cy + r2 * math.sin(ang)),
               fill=(214, 176, 80, 255), width=int(1.6 * s))
    # needle (about 80 %) with a dark outline, then the gold hub
    ang = math.radians(180 + 180 * 0.8)
    tip = (cx + (rad - 3 * s) * math.cos(ang), cy + (rad - 3 * s) * math.sin(ang))
    d.line((cx, cy, tip[0], tip[1]), fill=(10, 12, 16, 255), width=int(6.5 * s))
    d.line((cx, cy, tip[0], tip[1]), fill=(245, 245, 240, 255), width=int(3.2 * s))
    for r, col in ((7.5, (10, 12, 16, 255)), (6, (226, 176, 62, 255)), (3.2, (255, 238, 170, 255))):
        d.ellipse((cx - r * s, cy - r * s, cx + r * s, cy + r * s), fill=col)

    # percent capsule at the bottom
    cap = (c - 24 * s, c + 29 * s, c + 24 * s, c + 47 * s)
    d.rounded_rectangle(cap, radius=9 * s, fill=(8, 10, 15, 255), outline=(226, 176, 62, 255), width=int(1.8 * s))
    try:
        from PIL import ImageFont
        font = ImageFont.truetype(os.path.join(os.environ.get("WINDIR", "C:/Windows"), "Fonts", "arialbd.ttf"), int(13 * s))
        d.text((c, (cap[1] + cap[3]) / 2 + 0.5 * s), "70%", font=font, fill=(255, 255, 255, 255), anchor="mm")
    except OSError:
        pass

    # glass highlight on the upper rim
    shine = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(shine).ellipse((c - 46 * s, c - 58 * s, c + 46 * s, c - 6 * s), fill=(255, 255, 255, 26))
    big = Image.alpha_composite(big, shine)
    # 8 px transparent margin: in Titan Panel and the minimap the disc then matches the visual size of other
    # launcher icons (a full-bleed disc looked bigger and hung below the text line).
    inner = size - 16
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.alpha_composite(big.resize((inner, inner), Image.LANCZOS), (8, 8))
    return out


def main():
    assets = os.path.join(ROOT, "Assets")
    branding = os.path.join(ROOT, "docs", "branding")
    os.makedirs(assets, exist_ok=True)
    os.makedirs(branding, exist_ok=True)
    items = {
        "Tab_Fill": tab(128, 48),
        "Tab_Border": tab(128, 48, outline=3),
        "TrisThreatIcon": icon(),
    }
    for name, img in items.items():
        write_tga(os.path.join(assets, name + ".tga"), img)
        img.save(os.path.join(branding, name + ".png"))
        print("wrote", name)


if __name__ == "__main__":
    main()
