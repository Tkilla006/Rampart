"""Tactical character sheets: officers, suspects and civilians, built from the rookie officer sprite.

Civilians and suspects are recolors of the officer frames: the navy uniform becomes a shirt above the
belt line and pants below it, the badge, nameplate, patch and duty gear take the shirt or belt colors,
and skin and hair vary. Every sheet also gets a kneeling pose per facing and a downed (lying) frame.

Sheet layout (32x48 frames): rows down, left, right, up; columns idle, walk1-4, kneel.
Each sheet gets a Godot SpriteFrames .tres with idle_*, walk_*, kneel_* and down animations.
"""
import json
import sys
from pathlib import Path
from PIL import Image
import make_rookie as mr

W, H = mr.W, mr.H
ROWS = ["down", "left", "right", "up"]
HIP_Y = 30  # rows at or below this are pants

P = mr.PAL
UNIFORM = [P["N"], P["n"], P["L"]]
POLICE_BITS = [P["G"], P["P"]]
GEAR = [P["B"], P["b"], P["M"]]

SKINS = {
    "light": [(226, 180, 140), (186, 140, 104)],
    "medium": P["S"] and [P["S"], P["s"]],
    "tan": [(176, 124, 86), (140, 96, 64)],
    "dark": [(120, 82, 58), (90, 60, 42)],
}
HAIR = {"black": [(26, 22, 22), (52, 44, 40)], "brown": [P["H"], P["h"]], "gray": [(120, 120, 124), (160, 160, 164)],
        "blond": [(170, 140, 80), (206, 178, 112)]}


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c)


def ramp(c):
    return [c, shade(c, 0.72), shade(c, 1.25)]


# id: shirt, pants, shoes/belt, skin, hair, keep police details
PEOPLE = {
    "officer": None,
    "suspect_hoodie": ((96, 98, 104), (52, 66, 98), (24, 24, 26), "tan", "black"),
    "suspect_white_tee": ((214, 212, 204), (40, 40, 46), (30, 30, 32), "medium", "black"),
    "suspect_flannel": ((140, 46, 44), (70, 82, 110), (60, 44, 32), "light", "brown"),
    "suspect_tracksuit": ((30, 30, 34), (30, 30, 34), (220, 220, 220), "dark", "black"),
    "civilian_vendor": ((206, 170, 70), (84, 70, 56), (50, 40, 32), "tan", "black"),
    "civilian_nurse": ((92, 150, 160), (92, 150, 160), (220, 220, 214), "dark", "black"),
    "civilian_elder": ((150, 120, 140), (96, 92, 88), (40, 36, 34), "medium", "gray"),
    "civilian_clerk": ((60, 110, 70), (50, 50, 56), (30, 30, 32), "light", "blond"),
}


def recolor(sheet, spec):
    if spec is None:
        return sheet.copy()
    shirt, pants, shoes, skin, hair = spec
    out = sheet.copy()
    px = out.load()
    sr, pr = ramp(shirt), ramp(pants)
    sk, hr = SKINS[skin], HAIR[hair]
    for yy in range(out.height):
        local_y = yy % H
        for xx in range(out.width):
            c = px[xx, yy]
            if c[3] == 0:
                continue
            rgb = c[:3]
            new = None
            if rgb in UNIFORM:
                r = pr if local_y >= HIP_Y + 1 else sr
                new = r[UNIFORM.index(rgb)]
            elif rgb in POLICE_BITS:
                new = sr[0] if local_y < HIP_Y else pr[0]
            elif rgb == P["B"]:
                new = shoes if local_y >= 42 else shade(pants, 0.6)
            elif rgb == P["b"]:
                new = shade(shoes, 1.2) if local_y >= 42 else shade(pants, 0.7)
            elif rgb == P["M"]:
                new = shade(pants, 0.6)
            elif rgb == P["S"]:
                new = sk[0]
            elif rgb == P["s"]:
                new = sk[1]
            elif rgb == P["H"]:
                new = hr[0]
            elif rgb == P["h"]:
                new = hr[1]
            if new is not None:
                px[xx, yy] = tuple(new) + (255,)
    return out


def kneel_frame(frame):
    """Shortens the legs: keep the head and torso, drop them onto bent legs."""
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    upper = frame.crop((0, 0, W, 34))
    lower = frame.crop((0, 40, W, H))
    out.paste(upper, (0, 6), upper)
    out.paste(lower, (0, 40), lower)
    return out


def down_frame(frame):
    """A body lying on the ground: the idle front frame turned on its side and flattened."""
    body = frame.rotate(90, expand=True)  # 48 x 32
    body = body.resize((48, 18), Image.NEAREST)
    out = Image.new("RGBA", (W + 16, H), (0, 0, 0, 0))
    out.paste(body, (0, H - 22), body)
    return out


def build(out: Path, rookie_sheet: Path):
    out.mkdir(parents=True, exist_ok=True)
    base = Image.open(rookie_sheet).convert("RGBA")
    meta = {}
    for name, spec in PEOPLE.items():
        sheet = recolor(base, spec)
        full = Image.new("RGBA", (W * 6, H * 4), (0, 0, 0, 0))
        for r in range(4):
            for c in range(5):
                f = sheet.crop((c * W, r * H, (c + 1) * W, (r + 1) * H))
                full.paste(f, (c * W, r * H))
            k = kneel_frame(sheet.crop((0, r * H, W, (r + 1) * H)))
            full.paste(k, (5 * W, r * H))
        down = down_frame(sheet.crop((0, 0, W, H)))
        full.save(out / f"{name}_tac.png")
        down.save(out / f"{name}_down.png")
        write_frames(out / f"{name}_tac_frames.tres", name)
        meta[name] = {"sheet": f"{name}_tac.png", "down": f"{name}_down.png", "feet_px": [16, 46]}
    (out / "people_index.json").write_text(json.dumps(meta, indent=1))


def write_frames(path: Path, name: str):
    tex = f"res://art/characters/people/{name}_tac.png"
    down = f"res://art/characters/people/{name}_down.png"
    subs, anims, sid = [], [], 0
    for r, row in enumerate(ROWS):
        for kind, cols, speed in (("idle", [0], 1.0), ("walk", [1, 2, 3, 4], 8.0), ("kneel", [5], 1.0)):
            ids = []
            for c in cols:
                sid += 1
                subs.append(f'[sub_resource type="AtlasTexture" id="AtlasTexture_{sid}"]\n'
                            f'atlas = ExtResource("1_tex")\nregion = Rect2({c * W}, {r * H}, {W}, {H})\n')
                ids.append(sid)
            frames = ", ".join(f'{{\n"duration": 1.0,\n"texture": SubResource("AtlasTexture_{i}")\n}}' for i in ids)
            anims.append(f'{{\n"frames": [{frames}],\n"loop": true,\n"name": &"{kind}_{row}",\n"speed": {speed}\n}}')
    anims.append('{\n"frames": [{\n"duration": 1.0,\n"texture": ExtResource("2_down")\n}],\n"loop": true,\n"name": &"down",\n"speed": 1.0\n}')
    text = (f'[gd_resource type="SpriteFrames" load_steps={sid + 3} format=3]\n\n'
            f'[ext_resource type="Texture2D" path="{tex}" id="1_tex"]\n'
            f'[ext_resource type="Texture2D" path="{down}" id="2_down"]\n\n'
            + "\n".join(subs) + "\n[resource]\nanimations = [" + ", ".join(anims) + "]\n")
    path.write_text(text)


if __name__ == "__main__":
    build(Path(sys.argv[1]), Path(sys.argv[2]))
