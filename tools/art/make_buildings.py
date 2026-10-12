"""Buildings, interiors and civilian cars for tactical maps, in the street kit's style.

Walls sit on tile edges, X-COM style: an "x" wall runs along a tile's north edge (ground +x direction),
a "y" wall along its west edge (ground +y). One tile edge is 32 ground units (about 1.45 m).
Wall heights: full walls 44 voxels (2 m), low walls 14 (waist height).

Outputs (to the given directory):
  walls/<material>_<kind>_<axis>.png   kinds: plain, window, door, door_open, broken; axis x or y
  walls_anchors.json                   anchor pixel of each sprite's ground start point
  interior/<name>.png and rampart_interior_tiles.png (+ index json), 64x32 floor tiles
  props/<name>.png and objects_anchors.json   counter, shelf, low concrete wall, planter, mattress
  cars/sedan_<color>_<facing>.png and sedan_anchors.json   civilian sedans recolored from the Crown Vic model
"""
import json
import math
import sys
from pathlib import Path
import numpy as np
from PIL import Image
from voxel import Model, render, tones, anchor_px
import make_crownvic as cv
from make_street import TW, TH, vnoise, h, mix, shade

EDGE = 32
FULL_H = 44
LOW_H = 14
THICK = 3

MATERIALS = {
    "stucco": {"base": (198, 182, 150), "trim": (150, 136, 110)},
    "brick": {"base": (150, 72, 54), "trim": (96, 52, 42)},
    "drywall": {"base": (214, 210, 200), "trim": (170, 166, 158)},
    "storefront": {"base": (90, 92, 98), "trim": (60, 62, 68)},
}

PAL = {}
for name, m in MATERIALS.items():
    PAL[name] = tones(m["base"])
    PAL[name + "_trim"] = tones(m["trim"])
    PAL[name + "_mortar"] = tones(shade(m["base"], 0.78))
PAL.update({
    "glass": ((120, 150, 176), (86, 112, 138), (66, 88, 110)),
    "glass_hl": ((190, 214, 232), (150, 176, 196), (120, 144, 164)),
    "door": tones((112, 74, 46)), "door_d": tones((80, 52, 32)), "knob": tones((214, 190, 110)),
    "frame": tones((60, 54, 50)), "conc": tones((168, 164, 156)), "conc_d": tones((132, 128, 120)),
    "counter": tones((122, 90, 60)), "counter_top": tones((196, 186, 168)),
    "shelf": tones((110, 112, 120)), "goods_r": tones((196, 64, 52)), "goods_b": tones((60, 96, 170)),
    "goods_y": tones((226, 190, 70)), "goods_g": tones((80, 150, 90)),
    "soil": tones((92, 70, 52)), "plant": tones((70, 126, 64)),
    "mattress": tones((176, 168, 150)), "stain": tones((140, 120, 96)),
})


def wall_model(material, kind, height=FULL_H):
    m = Model(EDGE, THICK, height)
    x, y, z = m.x, m.y, m.z
    m.fill(np.ones(m.shape, bool), material)
    if material == "brick":
        course = (np.floor(z / 3) % 2).astype(int)
        mortar = ((z % 3) < 0.9) | (((x + course * 3) % 6) < 0.9)
        m.paint(mortar, "brick_mortar")
    m.paint(z > height - 2, material + "_trim")
    m.paint(z < 2, material + "_trim")
    if kind == "window":
        hole = (x > 8) & (x < 24) & (z > 14) & (z < 34)
        m.carve(hole)
        m.fill(hole & (np.abs(y - THICK / 2) < 0.6), "glass")
        frame = (((x > 7) & (x < 9)) | ((x > 23) & (x < 25)) | ((z > 13) & (z < 15)) | ((z > 33) & (z < 35))) \
            & (x > 7) & (x < 25) & (z > 13) & (z < 35)
        m.fill(frame, "frame")
    elif kind in ("door", "door_open"):
        hole = (x > 9) & (x < 23) & (z < 34)
        m.carve(hole)
        frame = (((x > 8) & (x < 10)) | ((x > 22) & (x < 24)) | ((z > 33) & (z < 35))) & (x > 8) & (x < 24) & (z < 35)
        m.fill(frame, "frame")
        if kind == "door":
            panel = hole & (np.abs(y - THICK / 2) < 0.8)
            m.fill(panel, "door")
            m.paint(panel & (z > 30), "door_d")
            m.fill((np.abs(x - 20) < 1) & (np.abs(z - 16) < 1) & (np.abs(y - THICK / 2) < 1.6), "knob")
    elif kind == "broken":
        rng = np.random.default_rng(7)
        cx, cz, r = 16, height * 0.55, height * 0.42
        noise = rng.random(m.shape) * 5
        m.carve(((x - cx) ** 2 + (z - cz) ** 2) < (r + noise) ** 2)
    elif kind == "storefront":
        pane = (x > 3) & (x < 29) & (z > 6) & (z < 38)
        m.carve(pane)
        m.fill(pane & (np.abs(y - THICK / 2) < 0.6), "glass")
    return m


def low_wall():
    m = Model(EDGE, 5, LOW_H)
    m.fill(np.ones(m.shape, bool), "conc")
    m.paint(m.z > LOW_H - 2, "conc_d")
    return m


def padded(model):
    """Copy a model into one with a one-voxel empty margin on x and y and above.

    The renderer's outline pass wraps around the image border, so models must not touch it.
    Ground anchors move by +1 on x and y.
    """
    X, Y, Z = model.shape
    p = Model(X + 2, Y + 2, Z + 1)
    p.keys = model.keys
    p.occ[1:-1, 1:-1, :Z] = model.occ
    p.col[1:-1, 1:-1, :Z] = model.col
    return p


def axis_variant(model, axis):
    """Models are built along +x; the y-axis variant is the same model rotated so it runs along +y."""
    t = model.shape[1]
    if axis == "x":
        return padded(model), (1.0, 1.0 + t / 2)
    # Rotated a quarter turn the wall runs along +y with its thickness on x; walls are symmetric end to end.
    return padded(model.rotated(1)), (1.0 + t / 2, 1.0)


# ---------------------------------------------------------------- props (tactical objects)
def counter():
    m = Model(60, 18, 20)
    m.fill((m.z < 18), "counter")
    m.fill((m.z >= 18), "counter_top")
    return m, (30, 9)


def shelf():
    m = Model(60, 14, 38)
    x, y, z = m.x, m.y, m.z
    m.fill(((z < 2) | ((z % 12) < 1.5) | (x < 2) | (x > 58)) & (y > 1), "shelf")
    m.fill((y < 2), "shelf")
    goods = (y > 3) & (y < 12) & (x > 3) & (x < 57) & ((z % 12) > 1.5) & ((z % 12) < 8)
    keys = ["goods_r", "goods_b", "goods_y", "goods_g"]
    for i, k in enumerate(keys):
        m.fill(goods & ((np.floor(x / 7) % 4) == i), k)
    return m, (30, 7)


def planter():
    m = Model(28, 28, 18)
    x, y, z = m.x, m.y, m.z
    m.fill((z < 12), "conc")
    m.carve((x > 3) & (x < 25) & (y > 3) & (y < 25) & (z > 9))
    m.fill((x > 3) & (x < 25) & (y > 3) & (y < 25) & (z > 9) & (z < 11), "soil")
    m.fill((((x - 14) ** 2 + (y - 14) ** 2) < 70) & (z >= 11) & (z < 18), "plant")
    return m, (14, 14)


def mattress():
    m = Model(44, 28, 4)
    m.fill(np.ones(m.shape, bool), "mattress")
    m.paint((((m.x - 18) ** 2 + (m.y - 12) ** 2) < 30) & (m.z > 2), "stain")
    return m, (22, 14)


OBJECTS = {"store_counter": counter, "store_shelf": shelf, "planter": planter, "mattress": mattress}


# ---------------------------------------------------------------- interior floor tiles
def floor_fn(name):
    if name == "linoleum":
        def f(x, y):
            check = (int(x // 8) + int(y // 8)) % 2
            c = (196, 192, 178) if check else (164, 158, 146)
            return shade(c, 0.94 + 0.08 * vnoise(x, y, 8, 3))
        return f
    if name == "wood_floor":
        def f(x, y):
            board = int(y // 5)
            c = mix((138, 98, 64), (112, 78, 50), h(board, int((x + board * 11) // 16), 5))
            if (y % 5) < 0.6:
                c = (84, 58, 38)
            return shade(c, 0.92 + 0.12 * vnoise(x, y, 4, board))
        return f
    if name == "carpet":
        def f(x, y):
            return shade((92, 74, 82), 0.9 + 0.16 * vnoise(x, y, 4, 9))
        return f
    if name == "concrete_floor":
        def f(x, y):
            return shade((140, 138, 132), 0.9 + 0.14 * vnoise(x, y, 8, 12))
        return f
    if name == "courtyard_tile":
        def f(x, y):
            c = (176, 132, 100) if (int(x // 16) + int(y // 16)) % 2 else (160, 118, 90)
            if (x % 16) < 0.8 or (y % 16) < 0.8:
                c = (120, 100, 84)
            return shade(c, 0.94 + 0.1 * vnoise(x, y, 8, 21))
        return f
    raise KeyError(name)


FLOORS = ["linoleum", "wood_floor", "carpet", "concrete_floor", "courtyard_tile"]


def render_floor(name):
    f = floor_fn(name)
    im = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
    pxs = im.load()
    for py in range(TH):
        for px in range(TW):
            U, V = px + 0.5 - 32, py + 0.5
            x, y = V + U / 2, V - U / 2
            if 0 <= x < 32 and 0 <= y < 32:
                pxs[px, py] = f(x, y) + (255,)
    return im


# ---------------------------------------------------------------- civilian cars
SEDAN_COLORS = {
    "maroon": (112, 34, 40), "silver": (168, 172, 178), "blue": (52, 74, 120),
    "white": (222, 222, 218), "green": (56, 92, 70), "tan": (176, 156, 120),
}


def sedan_palette(rgb):
    pal = dict(cv.PAL)
    body = tones(rgb, 1.0, 0.82, 0.62)
    for k in ("blk", "wht", "text", "sealg", "sealb", "push"):
        pal[k] = body
    for k in ("red", "blue", "lbw", "lbbase", "amber"):
        pal[k] = tones(shade(rgb, 0.7))
    return pal


def build(out: Path):
    out.mkdir(parents=True, exist_ok=True)
    (out / "walls").mkdir(exist_ok=True)
    (out / "interior").mkdir(exist_ok=True)
    (out / "props").mkdir(exist_ok=True)
    (out / "cars").mkdir(exist_ok=True)

    walls = {}
    kinds = {"stucco": ["plain", "window", "door", "door_open", "broken"],
             "brick": ["plain", "window", "door", "door_open", "broken"],
             "drywall": ["plain", "door", "door_open", "broken"],
             "storefront": ["storefront", "door", "door_open", "broken"]}
    for material, ks in kinds.items():
        for kind in ks:
            base = wall_model(material, kind)
            for axis in ("x", "y"):
                mm, anc = axis_variant(base, axis)
                im, origin = render(mm, PAL, shadow=False)
                name = f"{material}_{kind}_{axis}"
                im.save(out / "walls" / f"{name}.png")
                walls[name] = {"size": im.size, "anchor_px": [round(v, 1) for v in anchor_px(origin, *anc)]}
    for axis in ("x", "y"):
        mm, anc = axis_variant(low_wall(), axis)
        im, origin = render(mm, PAL)
        name = f"lowwall_plain_{axis}"
        im.save(out / "walls" / f"{name}.png")
        walls[name] = {"size": im.size, "anchor_px": [round(v, 1) for v in anchor_px(origin, *anc)]}
    (out / "walls_anchors.json").write_text(json.dumps(walls, indent=1))

    objects = {}
    for name, fn in OBJECTS.items():
        base, anc = fn()
        for k in (0, 1):
            mm = base.rotated(k)
            ax, ay = anc
            if k == 1:
                ax, ay = base.shape[1] - ay, ax
            fp = [mm.shape[0], mm.shape[1]]
            mm = padded(mm)
            ax, ay = ax + 1, ay + 1
            im, origin = render(mm, PAL)
            fname = f"{name}_r{k}"
            im.save(out / "props" / f"{fname}.png")
            objects[fname] = {"size": im.size, "ground_anchor_px": [round(v, 1) for v in anchor_px(origin, ax, ay)],
                              "footprint_units": fp}
    (out / "objects_anchors.json").write_text(json.dumps(objects, indent=1))

    atlas = Image.new("RGBA", (TW * len(FLOORS), TH), (0, 0, 0, 0))
    index = {}
    for i, name in enumerate(FLOORS):
        im = render_floor(name)
        im.save(out / "interior" / f"{name}.png")
        atlas.paste(im, (i * TW, 0))
        index[name] = [i, 0]
    atlas.save(out / "rampart_interior_tiles.png")
    (out / "rampart_interior_tiles_index.json").write_text(json.dumps(index, indent=1))

    base = cv.build_model()
    sedans = {}
    for color, rgb in SEDAN_COLORS.items():
        pal = sedan_palette(rgb)
        for k in range(4):
            mm = base.rotated(k)
            facing = cv.facing(mm)
            im, origin = render(mm, pal, highlight=cv.GLASS_HL)
            X, Y, _ = mm.shape
            ax, ay = anchor_px(origin, X / 2, Y / 2)
            fname = f"sedan_{color}_{facing}.png"
            im.save(out / "cars" / fname)
            sedans[f"{color}_{facing}"] = {"file": fname, "ground_center_px": [round(ax, 1), round(ay, 1)]}
    (out / "sedan_anchors.json").write_text(json.dumps(sedans, indent=1))


if __name__ == "__main__":
    build(Path(sys.argv[1]))
