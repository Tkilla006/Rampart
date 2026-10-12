"""Procedural pixel-art sprite sheet: LAPD rookie officer, 2010 navy uniform.

Frames are 32x48. Rows: down, left, right, up. Columns: idle, walk1..walk4.
Shapes are filled first, then an automatic outline pass draws the silhouette.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

W, H = 32, 48
PAL = {
    "K": (18, 20, 30),      # outline
    "N": (34, 44, 86),      # uniform navy
    "n": (24, 31, 62),      # navy shadow
    "L": (54, 68, 120),     # navy highlight
    "S": (205, 150, 110),   # skin
    "s": (168, 115, 82),    # skin shadow
    "H": (44, 30, 24),      # hair
    "h": (78, 55, 42),      # hair highlight
    "B": (22, 22, 26),      # black leather
    "b": (66, 66, 74),      # leather highlight
    "G": (222, 196, 112),   # badge / nameplate metal
    "M": (170, 176, 188),   # buckle, gun steel
    "E": (25, 25, 35),      # eyes
    "P": (110, 140, 190),   # shoulder patch
}

def blank():
    return [[None] * W for _ in range(H)]

def rect(g, x0, y0, x1, y1, c):
    for y in range(max(0, y0), min(H - 1, y1) + 1):
        for x in range(max(0, x0), min(W - 1, x1) + 1):
            g[y][x] = c

def px(g, x, y, c):
    if 0 <= x < W and 0 <= y < H:
        g[y][x] = c

def outline(g):
    out = [row[:] for row in g]
    for y in range(H):
        for x in range(W):
            if g[y][x] is None:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < W and 0 <= ny < H and g[ny][nx] not in (None, "K"):
                        out[y][x] = "K"
                        break
    return out

# Walk phases: (front leg, body bob). "A" = viewer-left / near leg forward.
PHASES = {"idle": (None, 0), "w1": ("A", 0), "w2": (None, -1), "w3": ("B", 0), "w4": (None, -1)}

def leg_column(g, x0, top, bottom, shoe_rows, color, shoe_dx=(0, 0)):
    rect(g, x0, top, x0 + 3, bottom, color)
    rect(g, x0 + shoe_dx[0], bottom + 1, x0 + 3 + shoe_dx[1], bottom + shoe_rows, "B")
    px(g, x0 + 1 + shoe_dx[0], bottom + 1, "b")

def front_or_back(phase, back=False):
    g = blank()
    fwd, bob = PHASES[phase]
    y = lambda v: v + bob
    hip = y(31)
    # legs: raised leg lifts 2px
    ll_bottom = 40 if fwd == "B" else 42
    rl_bottom = 40 if fwd == "A" else 42
    leg_column(g, 11, hip, ll_bottom, 3, "N", (-1, 0))
    leg_column(g, 17, hip, rl_bottom, 3, "N", (0, 1))
    rect(g, 14, hip, 14, ll_bottom, "n")
    rect(g, 17, hip, 17, rl_bottom, "n")
    # torso
    rect(g, 11, y(20), 20, y(31), "N")
    rect(g, 12, y(19), 19, y(19), "N")
    rect(g, 11, y(21), 11, y(28), "L" if not back else "N")
    rect(g, 20, y(21), 20, y(28), "n")
    if not back:
        rect(g, 15, y(20), 15, y(28), "n")             # placket
        rect(g, 12, y(22), 14, y(22), "n")             # pocket flaps
        rect(g, 17, y(22), 19, y(22), "n")
        rect(g, 18, y(23), 19, y(24), "G")             # badge, officer's left chest
        rect(g, 12, y(25), 14, y(25), "G")             # nameplate, officer's right
        px(g, 20, y(20), "B")                          # shoulder mic
    else:
        rect(g, 12, y(23), 19, y(23), "n")             # back yoke seam
    # duty belt
    rect(g, 11, y(29), 20, y(30), "B")
    if not back:
        rect(g, 15, y(29), 16, y(30), "M")
    # holster on officer's right hip, radio on left hip
    hx = 10 if not back else 20
    rx = 20 if not back else 10
    rect(g, hx, y(29), hx + 1, y(34), "B")
    px(g, hx, y(29), "b"); px(g, hx + 1, y(29), "b")
    rect(g, rx, y(30), rx + 1, y(32), "B")
    px(g, rx + (1 if not back else 0), y(28), "B")    # radio antenna
    # arms (swing opposite to legs)
    l_off = -1 if fwd == "A" else (1 if fwd == "B" else 0)
    r_off = -l_off
    for ax, off, shade_x in ((7, l_off, 9), (22, r_off, 22)):
        rect(g, ax, y(20), ax + 2, y(29) + off, "N")
        rect(g, shade_x, y(21), shade_x, y(29) + off, "n")
        rect(g, ax, y(21), ax + 2, y(21), "P")          # shoulder patch band
        rect(g, ax, y(30) + off, ax + 2, y(31) + off, "S")
        rect(g, ax, y(31) + off, ax + 2, y(31) + off, "s")
    # neck and head
    rect(g, 14, y(16), 17, y(19), "s" if back else "S")
    if not back:
        px(g, 13, y(19), "N"); px(g, 18, y(19), "N")   # open collar
    rect(g, 11, y(6), 20, y(16), "S")
    for cx, cy in ((11, 6), (20, 6), (11, 16), (20, 16)):
        g[y(cy)][cx] = None
    rect(g, 10, y(10), 10, y(12), "s"); rect(g, 21, y(10), 21, y(12), "s")  # ears
    rect(g, 12, y(5), 19, y(5), "H")
    if back:
        rect(g, 11, y(6), 20, y(14), "H")
        rect(g, 12, y(15), 19, y(15), "H")
        rect(g, 13, y(7), 16, y(7), "h")
    else:
        rect(g, 11, y(6), 20, y(8), "H")
        rect(g, 11, y(9), 11, y(11), "H"); rect(g, 20, y(9), 20, y(11), "H")
        rect(g, 14, y(6), 16, y(6), "h")
        rect(g, 13, y(10), 14, y(10), "H"); rect(g, 17, y(10), 18, y(10), "H")  # brows
        px(g, 13, y(11), "E"); px(g, 18, y(11), "E")
        rect(g, 15, y(14), 16, y(14), "s")                                      # mouth
        rect(g, 12, y(16) - 1, 19, y(16) - 1, "S")
        rect(g, 12, y(16), 19, y(16), "s")                                      # jaw shade
    return outline(g)

def lerp(a, b, t):
    return round(a + (b - a) * t)

def slanted_leg(g, hip_x, foot_x, top, bottom, color, toe=2):
    for yy in range(top, bottom + 1):
        t = (yy - top) / max(1, bottom - top)
        x0 = lerp(hip_x, foot_x, t)
        rect(g, x0, yy, x0 + 3, yy, color)
    fx = foot_x
    rect(g, fx, bottom + 1, fx + 3 + toe, bottom + 3, "B")
    px(g, fx + 1, bottom + 1, "b")

def side(phase):
    """Facing right. The officer's right side (holster) faces the viewer."""
    g = blank()
    fwd, bob = PHASES[phase]
    y = lambda v: v + bob
    hip = y(31)
    if fwd is None:
        lift = 2 if bob else 0
        slanted_leg(g, 14, 13, hip, 42 - lift, "n")              # far leg, tucked when passing
        slanted_leg(g, 14, 15, hip, 42, "N")                     # near leg
    else:
        near_fwd = fwd == "A"
        far_x, near_x = (10, 18) if near_fwd else (18, 10)
        slanted_leg(g, 14, far_x, hip, 42, "n")
        slanted_leg(g, 14, near_x, hip, 42, "N")
    # torso
    rect(g, 13, y(20), 19, y(31), "N")
    rect(g, 14, y(19), 18, y(19), "N")
    rect(g, 19, y(21), 19, y(28), "n")
    rect(g, 13, y(29), 19, y(30), "B")                            # belt
    rect(g, 12, y(29), 13, y(30), "B")
    rect(g, 14, y(29), 16, y(34), "B")                            # holster
    px(g, 14, y(29), "M"); px(g, 15, y(29), "b")                  # gun grip
    # head
    rect(g, 16, y(17), 18, y(19), "S")
    rect(g, 12, y(6), 20, y(16), "S")
    for cx, cy in ((12, 6), (20, 6), (12, 16), (20, 16)):
        g[y(cy)][cx] = None
    rect(g, 13, y(5), 19, y(5), "H")
    rect(g, 12, y(6), 20, y(8), "H")
    rect(g, 12, y(9), 15, y(14), "H")
    rect(g, 13, y(15), 15, y(15), "H")
    rect(g, 15, y(6), 17, y(6), "h")
    rect(g, 15, y(10), 15, y(12), "s")                            # ear
    px(g, 18, y(10), "H"); px(g, 19, y(10), "H")                  # brow
    px(g, 18, y(11), "E")
    px(g, 21, y(12), "S"); px(g, 21, y(13), "s")                  # nose
    rect(g, 19, y(14), 20, y(14), "s")                            # mouth
    rect(g, 16, y(16), 19, y(16), "s")
    # near arm swings opposite the near leg
    dx = 0 if fwd is None else (-2 if fwd == "A" else 2)
    rect(g, 15, y(20), 17, y(24), "N")
    rect(g, 15, y(21), 17, y(21), "P")
    for yy in range(y(25), y(29) + 1):
        t = (yy - y(25)) / 4
        x0 = 15 + round(dx * t)
        rect(g, x0, yy, x0 + 2, yy, "N")
        px(g, x0 + 2, yy, "n")
    hx = 15 + dx
    rect(g, hx, y(30), hx + 2, y(31), "S")
    rect(g, hx, y(31), hx + 2, y(31), "s")
    return outline(g)

def mirror(g):
    return [list(reversed(row)) for row in g]

def to_image(g):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for yy in range(H):
        for xx in range(W):
            c = g[yy][xx]
            if c:
                img.putpixel((xx, yy), PAL[c] + (255,))
    return img

def build(out_dir: Path):
    order = ["idle", "w1", "w2", "w3", "w4"]
    rows = {
        "down": [front_or_back(p) for p in order],
        "right": [side(p) for p in order],
        "up": [front_or_back(p, back=True) for p in order],
    }
    rows["left"] = [mirror(f) for f in rows["right"]]
    row_names = ["down", "left", "right", "up"]
    sheet = Image.new("RGBA", (W * len(order), H * len(row_names)), (0, 0, 0, 0))
    for r, name in enumerate(row_names):
        for c, g in enumerate(rows[name]):
            sheet.paste(to_image(g), (c * W, r * H))
    out_dir.mkdir(parents=True, exist_ok=True)
    sheet.save(out_dir / "rookie_officer.png")

    # Preview: 6x, grey checker, labels
    S = 6
    big = sheet.resize((sheet.width * S, sheet.height * S), Image.NEAREST)
    pad_l, pad_t = 90, 40
    prev = Image.new("RGB", (big.width + pad_l + 20, big.height + pad_t + 20), (58, 62, 70))
    d = ImageDraw.Draw(prev)
    for r in range(len(row_names)):
        for c in range(len(order)):
            x0, y0 = pad_l + c * W * S, pad_t + r * H * S
            d.rectangle([x0, y0, x0 + W * S - 1, y0 + H * S - 1],
                        fill=(72, 77, 86) if (r + c) % 2 else (66, 70, 79))
    prev.paste(big, (pad_l, pad_t), big)
    for c, lab in enumerate(["idle", "walk 1", "walk 2", "walk 3", "walk 4"]):
        d.text((pad_l + c * W * S + 8, 14), lab, fill=(220, 220, 220))
    for r, lab in enumerate(row_names):
        d.text((12, pad_t + r * H * S + H * S // 2), lab, fill=(220, 220, 220))
    prev.save(out_dir / "rookie_officer_preview.png")

    # Animated walk GIF, 4 directions side by side
    frames = []
    for i in range(1, 5):
        f = Image.new("RGBA", (W * 4, H), (66, 70, 79, 255))
        for k, name in enumerate(row_names):
            fr = to_image(rows[name][i])
            f.paste(fr, (k * W, 0), fr)
        frames.append(f.resize((f.width * 6, f.height * 6), Image.NEAREST).convert("P", palette=Image.ADAPTIVE))
    frames[0].save(out_dir / "rookie_officer_walk.gif", save_all=True, append_images=frames[1:],
                   duration=140, loop=0, disposal=2)

    # Godot 4 SpriteFrames resource
    tex_path = "res://art/characters/rookie_officer.png"
    subs, anims, sid = [], [], 0
    for r, name in enumerate(row_names):
        for kind, cols, speed in (("idle", [0], 1.0), ("walk", [1, 2, 3, 4], 7.0)):
            ids = []
            for c in cols:
                sid += 1
                subs.append(f'[sub_resource type="AtlasTexture" id="AtlasTexture_{sid}"]\n'
                            f'atlas = ExtResource("1_tex")\nregion = Rect2({c * W}, {r * H}, {W}, {H})\n')
                ids.append(sid)
            frames_txt = ", ".join(f'{{\n"duration": 1.0,\n"texture": SubResource("AtlasTexture_{i}")\n}}' for i in ids)
            anims.append(f'{{\n"frames": [{frames_txt}],\n"loop": true,\n"name": &"{kind}_{name}",\n"speed": {speed}\n}}')
    tres = (f'[gd_resource type="SpriteFrames" load_steps={sid + 2} format=3]\n\n'
            f'[ext_resource type="Texture2D" path="{tex_path}" id="1_tex"]\n\n'
            + "\n".join(subs) + "\n[resource]\nanimations = [" + ", ".join(anims) + "]\n")
    (out_dir / "rookie_officer_frames.tres").write_text(tres)

if __name__ == "__main__":
    build(Path(sys.argv[1]))
