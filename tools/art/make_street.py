"""Rampart street kit: 64x32 isometric ground tiles, voxel street props, and a test intersection.

Scale: one tile = 32 x 32 ground units, about 1.45 m square (22 units per meter),
matching the officer sprite and the Crown Vic.
"""
import json
import math
import sys
from pathlib import Path
import numpy as np
from PIL import Image
from voxel import Model, render, tones, anchor_px

TW, TH = 64, 32

# ---------------------------------------------------------------- noise
def h(ix, iy, seed=0):
    n = (ix * 374761393 + iy * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0

def vnoise(x, y, cell, seed, period=32):
    """Tileable value noise over a 32-unit tile."""
    gx, gy = x / cell, y / cell
    x0, y0 = math.floor(gx), math.floor(gy)
    fx, fy = gx - x0, gy - y0
    p = period // cell
    def g(a, b):
        return h(a % p, b % p, seed)
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a = g(x0, y0) + (g(x0 + 1, y0) - g(x0, y0)) * sx
    b = g(x0, y0 + 1) + (g(x0 + 1, y0 + 1) - g(x0, y0 + 1)) * sx
    return a + (b - a) * sy

def mix(c1, c2, t):
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))

def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c)

# ---------------------------------------------------------------- materials
ASPH = [(46, 47, 52), (56, 57, 62), (64, 65, 70), (76, 77, 82)]
CONC = [(132, 128, 120), (152, 148, 140), (166, 162, 154), (180, 176, 168)]

def asphalt(x, y, seed=1, worn=0.0):
    n = vnoise(x, y, 8, seed) * 0.6 + vnoise(x, y, 4, seed + 7) * 0.4
    r = h(int(x * 2), int(y * 2), seed + 3)
    i = 1 if n < 0.55 else 2
    if r > 0.93:
        i = 3
    elif r < 0.06:
        i = 0
    c = ASPH[i]
    if worn:
        c = mix(c, (92, 90, 86), worn * vnoise(x, y, 16, seed + 11))
    return c

def concrete(x, y, seed=2):
    n = vnoise(x, y, 8, seed)
    r = h(int(x * 2), int(y * 2), seed + 5)
    c = CONC[2] if n > 0.4 else CONC[1]
    if r > 0.95:
        c = CONC[3]
    elif r < 0.04:
        c = CONC[0]
    return c

def paint(x, y, color, seed):
    """Worn road paint: mostly solid, with grit showing through."""
    if h(int(x * 2), int(y * 2), seed) < 0.06:
        return None
    return mix(color, (140, 138, 130), 0.18 * vnoise(x, y, 4, seed))

WHITE = (226, 224, 214)
YELLOW = (222, 178, 52)
RED = (176, 52, 46)

def near_poly(x, y, pts, w):
    best = 1e9
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        dx, dy = bx - ax, by - ay
        t = max(0, min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
        best = min(best, math.hypot(x - ax - t * dx, y - ay - t * dy))
    return best < w

CRACK_A = [(2, 6), (7, 9), (11, 8), (15, 13), (19, 14), (22, 19), (27, 21), (31, 26)]
CRACK_B = [(30, 3), (25, 7), (23, 12), (17, 17), (14, 23), (9, 25), (6, 31)]

# edges named by screen direction: NW is x=0, NE is y=0, SE is x=31, SW is y=31
def edge_dist(x, y, edge):
    return {"NW": x, "NE": y, "SE": 32 - x, "SW": 32 - y}[edge]

def tile_fn(name):
    if name == "asphalt":
        return lambda x, y: asphalt(x, y, 1)
    if name == "asphalt_cracked":
        def f(x, y):
            if near_poly(x, y, CRACK_A, 0.7) or near_poly(x, y, CRACK_B, 0.6):
                return (30, 30, 34)
            return asphalt(x, y, 2)
        return f
    if name == "asphalt_patched":
        def f(x, y):
            if 6 < x < 22 and 10 < y < 26:
                c = asphalt(x, y, 9)
                c = shade(c, 0.82)
                if abs(x - 6.5) < 0.8 or abs(x - 21.5) < 0.8 or abs(y - 10.5) < 0.8 or abs(y - 25.5) < 0.8:
                    c = (34, 34, 38)
                return c
            if (x - 24) ** 2 / 30 + (y - 6) ** 2 / 14 < 1:
                return (36, 36, 40) if h(int(x), int(y), 4) > 0.3 else (44, 44, 52)
            return asphalt(x, y, 3)
        return f
    if name in ("lane_dash_x", "lane_dash_y"):
        along_x = name.endswith("x")
        def f(x, y):
            a, b = (x, y) if along_x else (y, x)
            if 4 <= a <= 28 and abs(b - 16) <= 1.2:
                c = paint(x, y, WHITE, 21)
                if c:
                    return c
            return asphalt(x, y, 1)
        return f
    if name in ("double_yellow_x", "double_yellow_y"):
        along_x = name.endswith("x")
        def f(x, y):
            b = y if along_x else x
            if abs(b - 13.6) <= 1.1 or abs(b - 18.4) <= 1.1:
                c = paint(x, y, YELLOW, 22)
                if c:
                    return c
            return asphalt(x, y, 1)
        return f
    if name in ("crosswalk_x", "crosswalk_y"):
        # road runs along the named axis; bars run with traffic
        along_x = name.endswith("x")
        def f(x, y):
            b = y if along_x else x
            if 2 <= b <= 12 or 18 <= b <= 28:
                c = paint(x, y, WHITE, 23)
                if c:
                    return c
            return asphalt(x, y, 1)
        return f
    if name in ("stop_line_x", "stop_line_y"):
        along_x = name.endswith("x")
        def f(x, y):
            a = x if along_x else y
            if 12 <= a <= 17:
                c = paint(x, y, WHITE, 25)
                if c:
                    return c
            return asphalt(x, y, 1)
        return f
    if name == "manhole":
        def f(x, y):
            r = math.hypot(x - 16, y - 16)
            if r < 8.5:
                if r > 7.6:
                    return (40, 38, 38)
                ring = (int(r) % 2 == 0)
                c = (74, 70, 66) if ring else (58, 55, 52)
                if h(int(x), int(y), 31) > 0.85:
                    c = (110, 74, 48)  # rust
                return c
            if r < 9.6:
                return (52, 52, 56)
            return asphalt(x, y, 4)
        return f
    if name == "sidewalk":
        def f(x, y):
            if x < 0.9 or y < 0.9:
                return (118, 114, 106)
            if abs(x - 16) < 0.45 or abs(y - 16) < 0.45:
                return (140, 136, 128)
            return concrete(x, y, 2)
        return f
    if name == "sidewalk_stained":
        def f(x, y):
            if x < 0.9 or y < 0.9:
                return (118, 114, 106)
            if near_poly(x, y, [(18, 2), (20, 9), (17, 15), (21, 22), (19, 30)], 0.55):
                return (104, 100, 94)
            for gx, gy in ((6, 7), (9, 22), (25, 12), (27, 26), (13, 13), (5, 28)):
                if (x - gx) ** 2 + (y - gy) ** 2 < 1.4:
                    return (92, 90, 88)  # gum
            if (x - 10) ** 2 / 24 + (y - 18) ** 2 / 14 < 1:
                return shade(concrete(x, y, 6), 0.84)
            return concrete(x, y, 5)
        return f
    for paint_red in (False, True):
        for edge in ("NW", "NE", "SE", "SW"):
            for drain in (False, True):
                if drain and paint_red:
                    continue
                nm = ("curb_red_" if paint_red else ("storm_drain_" if drain else "curb_")) + edge
                if name == nm:
                    return curb_fn(edge, paint_red, drain)
    if name == "parkway_grass":
        def f(x, y):
            n = vnoise(x, y, 4, 41)
            if vnoise(x, y, 8, 42) < 0.3:
                return (128, 108, 78) if h(int(x * 2), int(y * 2), 43) > 0.5 else (116, 96, 68)
            g = [(70, 104, 50), (86, 120, 58), (104, 132, 64), (128, 138, 72)]
            k = min(3, int(n * 3.2 + h(int(x * 2), int(y * 2), 44) * 1.2))
            return g[k]
        return f
    if name == "alley":
        def f(x, y):
            if (x - 20) ** 2 / 40 + (y - 12) ** 2 / 18 < 1 and h(int(x), int(y), 51) > 0.2:
                return (40, 40, 44)  # oil
            if near_poly(x, y, [(0, 20), (8, 18), (14, 22), (24, 21), (32, 25)], 0.6):
                return (36, 36, 40)
            c = asphalt(x, y, 6, worn=0.8)
            if h(int(x * 2), int(y * 2), 52) > 0.985:
                return (150, 120, 70)  # litter
            return c
        return f
    if name == "dirt":
        def f(x, y):
            n = vnoise(x, y, 8, 61)
            d = [(104, 82, 60), (120, 96, 70), (136, 110, 80), (152, 126, 92)]
            k = min(3, int(n * 3 + h(int(x * 2), int(y * 2), 62) * 1.3))
            if h(int(x * 2), int(y * 2), 63) > 0.97:
                return (170, 160, 146)  # pebble
            return d[k]
        return f
    if name == "dirt_weeds":
        base = tile_fn("dirt")
        def f(x, y):
            if vnoise(x, y, 4, 71) > 0.62 and h(int(x * 2), int(y * 2), 72) > 0.35:
                return (150, 140, 76) if h(int(x * 2), int(y * 2), 73) > 0.5 else (120, 116, 62)
            return base(x, y)
        return f
    if name in ("rubble", "rubble_heavy"):
        base = tile_fn("dirt")
        dense = name == "rubble_heavy"
        chunks = []
        rnd = 81 if dense else 91
        for i in range(14 if dense else 7):
            cx, cy = 3 + h(i, 1, rnd) * 26, 3 + h(i, 2, rnd) * 26
            rx, ry = 1.6 + h(i, 3, rnd) * (4 if dense else 2.6), 1.4 + h(i, 4, rnd) * 2.4
            chunks.append((cx, cy, rx, ry, i))
        def f(x, y):
            for cx, cy, rx, ry, i in chunks:
                v = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
                if v < 1:
                    c = CONC[1 + i % 3]
                    if x - cx < -rx * 0.3 and y - cy < 0:
                        c = CONC[3]
                    elif x - cx > rx * 0.3 or y - cy > ry * 0.4:
                        c = shade(c, 0.7)
                    return c
            if near_poly(x, y, [(5, 26), (11, 22), (16, 24)], 0.45) or \
                    (dense and near_poly(x, y, [(20, 4), (24, 12), (29, 13)], 0.45)):
                return (124, 70, 44)  # rebar
            if h(int(x * 2), int(y * 2), rnd + 9) > 0.975:
                return (170, 166, 156)  # dust and grit
            return shade(base(x, y), 0.95)
        return f
    raise KeyError(name)

def curb_fn(edge, red, drain):
    def f(x, y):
        d = edge_dist(x, y, edge)
        faces_viewer = edge in ("SE", "SW")
        top_c = RED if red else (194, 190, 182)
        face_c = shade(RED, 0.7) if red else (112, 108, 102)
        along = y if edge in ("NW", "SE") else x
        if d < 4.2:
            if drain and 7 <= along <= 25 and d < 2.2:
                return (16, 16, 18) if d < 1.6 else (60, 58, 56)
            if faces_viewer:
                if d < 1.6:
                    return face_c
                if d < 2.4:
                    return shade(top_c, 1.04)
                return top_c if h(int(x * 2), int(y * 2), 101) > 0.08 else shade(top_c, 0.9)
            else:
                if d < 0.9:
                    return (70, 68, 66)
                return top_c if h(int(x * 2), int(y * 2), 102) > 0.08 else shade(top_c, 0.9)
        if d < 5.0:
            return (126, 122, 114)
        if drain and 9 <= along <= 23 and 5.5 <= d <= 7.5 and int(along) % 2 == 0:
            return (90, 120, 150)  # "drains to ocean" stencil
        g = tile_fn("sidewalk")
        return g(x, y)
    return f

TILES = [
    "asphalt", "asphalt_cracked", "asphalt_patched", "manhole",
    "lane_dash_x", "lane_dash_y", "double_yellow_x", "double_yellow_y",
    "crosswalk_x", "crosswalk_y", "stop_line_x", "stop_line_y",
    "sidewalk", "sidewalk_stained", "parkway_grass", "alley",
    "curb_NW", "curb_NE", "curb_SE", "curb_SW",
    "curb_red_NW", "curb_red_NE", "curb_red_SE", "curb_red_SW",
    "storm_drain_NW", "storm_drain_NE", "storm_drain_SE", "storm_drain_SW",
    "dirt", "dirt_weeds", "rubble", "rubble_heavy",
]

def render_tile(name):
    f = tile_fn(name)
    im = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
    pxs = im.load()
    for py in range(TH):
        for px in range(TW):
            U, V = px + 0.5 - 32, py + 0.5
            x, y = V + U / 2, V - U / 2
            if 0 <= x < 32 and 0 <= y < 32:
                pxs[px, py] = f(x, y) + (255,)
    return im

# ---------------------------------------------------------------- props
def P(rgb, **k):
    return tones(rgb, **k)

PROP_PAL = {
    "steel": P((150, 152, 158)), "steel_d": P((96, 98, 104)), "conc": P((172, 168, 160)),
    "lamp": ((255, 246, 200), (240, 226, 170), (220, 204, 150)),
    "trunk": P((136, 118, 98)), "trunk_d": P((106, 90, 74)), "skirt": P((132, 100, 62)),
    "skirt_d": P((100, 74, 46)), "frond": P((74, 122, 62)), "frond_l": P((112, 152, 72)),
    "frond_dead": P((150, 126, 72)),
    "hyd": P((222, 190, 64)), "hyd_cap": P((176, 178, 184)),
    "bin": P((44, 74, 56)), "bin_d": P((28, 48, 36)), "slot": P((16, 18, 18)),
    "dump": P((50, 104, 70)), "dump_d": P((36, 78, 52)), "lid": P((28, 28, 32)), "rust": P((128, 76, 44)),
    "wheel": P((30, 30, 32)),
    "bench": P((176, 172, 164)), "ad_w": P((236, 236, 230)), "ad_b": P((40, 86, 170)),
    "ad_y": P((242, 196, 58)), "ad_t": P((24, 26, 34)),
    "cone": P((244, 112, 34)), "cone_w": P((236, 236, 232)), "cone_b": P((34, 34, 36)),
    "fence": P((168, 172, 178)), "wire": P((140, 146, 152)),
}

def cyl(m, cx, cy, r, z0, z1, k, rfun=None):
    rr = r if rfun is None else rfun(m.z)
    m.fill(((m.x - cx) ** 2 + (m.y - cy) ** 2 <= rr ** 2) & (m.z >= z0) & (m.z <= z1), k)

def hydrant():
    m = Model(14, 14, 20)
    cyl(m, 7, 7, 4.2, 0, 1.5, "hyd_cap")
    cyl(m, 7, 7, 3.2, 1.5, 13, "hyd")
    cyl(m, 7, 7, 0, 13, 16, "hyd", lambda z: np.sqrt(np.clip(3.2 ** 2 - ((z - 13) * 1.1) ** 2, 0, None)))
    cyl(m, 7, 7, 1.1, 15, 17, "hyd_cap")
    m.fill((m.x > 9) & (m.x <= 12) & (np.abs(m.y - 7) <= 1.6) & (np.abs(m.z - 10) <= 1.6), "hyd_cap")
    m.fill((m.y > 9) & (m.y <= 12) & (np.abs(m.x - 7) <= 1.3) & (np.abs(m.z - 10) <= 1.3), "hyd_cap")
    m.fill((m.x < 5) & (m.x >= 2) & (np.abs(m.y - 7) <= 1.3) & (np.abs(m.z - 10) <= 1.3), "hyd_cap")
    return m, (7, 7)

def streetlight():
    m = Model(64, 14, 196)
    cyl(m, 7, 7, 3.4, 0, 8, "conc")
    cyl(m, 7, 7, 0, 8, 178, "steel", lambda z: 2.0 - (z - 8) / 170 * 0.8)
    t = (m.x - 7) / 44
    arm = (m.x >= 7) & (m.x <= 51) & (np.abs(m.y - 7) <= 1.0) & (np.abs(m.z - (172 + 6 * np.sqrt(np.clip(t, 0, 1)))) <= 1.0)
    m.fill(arm, "steel")
    head = (m.x >= 46) & (m.x <= 62) & (np.abs(m.y - 7) <= 3.2) & (m.z >= 175) & (m.z <= 180.5)
    head &= ((m.x - 54) / 8.5) ** 2 + ((m.y - 7) / 3.4) ** 2 <= 1
    m.fill(head, "steel_d")
    m.paint(head & (m.z < 176.2), "lamp")
    return m, (7, 7)

def palm():
    m = Model(70, 70, 214)
    cx = lambda z: 35 + 5 * (z / 190) ** 2
    trunk_r = lambda z: 3.4 - z / 190 * 1.1
    tr = ((m.x - cx(m.z)) ** 2 + (m.y - 35) ** 2 <= trunk_r(m.z) ** 2) & (m.z <= 176)
    m.fill(tr, "trunk")
    m.paint(tr & (np.floor(m.z) % 4 == 0), "trunk_d")
    sk_r = np.interp(m.z, [150, 166, 182], [4.5, 8.5, 9.5])
    sk = ((m.x - cx(m.z)) ** 2 + (m.y - 35) ** 2 <= sk_r ** 2) & (m.z >= 150) & (m.z <= 182)
    m.fill(sk, "skirt")
    m.paint(sk & (np.floor(m.x + m.y + m.z * 0.5) % 3 == 0), "skirt_d")
    c0 = (cx(184), 35, 184)
    occ = m.occ
    for i in range(18):
        a = i * 2 * math.pi / 18 + h(i, 1, 5) * 0.3
        dead = i in (4, 13)
        rise = 3 + h(i, 2, 5) * 4
        stem = 15
        ex, ey, ez = c0[0] + math.cos(a) * stem, c0[1] + math.sin(a) * stem, c0[2] + rise
        for s in np.linspace(0, 1, 30):
            px_, py_, pz_ = c0[0] + (ex - c0[0]) * s, c0[1] + (ey - c0[1]) * s, c0[2] + rise * s
            ix, iy, iz = int(px_), int(py_), int(pz_)
            if 0 <= ix < 70 and 0 <= iy < 70 and 0 <= iz < 214:
                occ[ix, iy, iz] = True
                m.col[ix, iy, iz] = m.key("frond_dead" if dead else "frond")
        for d in np.arange(0, 17, 0.5):
            for phi in np.radians(np.arange(-56, 57, 8)):
                ang = a + phi * (d / 17) * 0.8
                px_ = ex + math.cos(ang) * d
                py_ = ey + math.sin(ang) * d
                pz_ = ez - (d * d) / (13 if not dead else 6) - abs(phi) * 1.2
                ix, iy, iz = int(px_), int(py_), int(pz_)
                if 0 <= ix < 70 and 0 <= iy < 70 and 0 <= iz < 214:
                    occ[ix, iy, iz] = True
                    k = "frond_dead" if dead else ("frond_l" if (d > 11 or h(ix, iy, iz) > 0.8) else "frond")
                    m.col[ix, iy, iz] = m.key(k)
    return m, (35, 35)

def trash_can():
    m = Model(12, 12, 24)
    cyl(m, 6, 6, 4.4, 0, 19, "bin")
    m.paint((m.z <= 19) & (np.floor(np.degrees(np.arctan2(m.y - 6, m.x - 6)) / 30) % 2 == 0), "bin_d")
    cyl(m, 6, 6, 0, 19, 23, "bin_d", lambda z: np.sqrt(np.clip(4.6 ** 2 - ((z - 19) * 1.3) ** 2, 0, None)))
    m.paint((m.z >= 19.5) & (m.z <= 21) & (m.x > 9), "slot")
    m.paint((m.z >= 19.5) & (m.z <= 21) & (m.y > 9), "slot")
    return m, (6, 6)

def dumpster():
    m = Model(46, 30, 32)
    box = (m.x >= 3) & (m.x <= 43) & (m.y >= 3) & (m.y <= 27) & (m.z >= 3) & (m.z <= 26)
    m.fill(box, "dump")
    m.paint(box & (np.floor(m.x) % 8 == 0), "dump_d")
    m.paint(box & (((m.x - 30) ** 2 + (m.z - 8) ** 2) < 9), "rust")
    m.paint(box & (((m.x - 12) ** 2 + (m.z - 20) ** 2) < 4), "rust")
    lid = (m.x >= 2) & (m.x <= 44) & (m.y >= 2) & (m.y <= 28) & (m.z > 26) & (m.z <= 26 + 3 * (28 - m.y) / 26)
    m.fill(lid, "lid")
    for wx in (6, 40):
        for wy in (6, 24):
            cyl(m, wx, wy, 2.2, 0, 3, "wheel")
    return m, (23, 15)

def bench():
    m = Model(44, 16, 28)
    seat = (m.x >= 1) & (m.x <= 43) & (m.y >= 2) & (m.y <= 11) & (m.z >= 8) & (m.z <= 10)
    m.fill(seat, "bench")
    for lx in (5, 39):
        m.fill((np.abs(m.x - lx) <= 2.5) & (m.y >= 3) & (m.y <= 10) & (m.z < 8), "bench")
    back = (m.x >= 1) & (m.x <= 43) & (m.y >= 11) & (m.y <= 13.5) & (m.z >= 10) & (m.z <= 26)
    m.fill(back, "ad_w")
    panel = back & (m.x >= 3) & (m.x <= 41) & (m.z >= 12) & (m.z <= 24)
    m.paint(panel, "ad_b")
    m.paint(panel & (m.x >= 5) & (m.x <= 22) & (m.z >= 19) & (m.z <= 22), "ad_y")
    m.paint(panel & (m.x >= 5) & (m.x <= 30) & (m.z >= 14) & (m.z <= 16) & (np.floor(m.x) % 3 != 0), "ad_w")
    m.paint(panel & (m.x >= 30) & (m.x <= 39) & (m.z >= 17) & (m.z <= 23), "ad_y")
    return m, (22, 8)

def cone():
    m = Model(12, 12, 20)
    m.fill((m.x >= 1.5) & (m.x <= 10.5) & (m.y >= 1.5) & (m.y <= 10.5) & (m.z <= 1.5), "cone_b")
    cyl(m, 6, 6, 0, 1.5, 17, "cone", lambda z: 3.8 - (z - 1.5) / 15.5 * 3.0)
    m.paint((m.z >= 8) & (m.z <= 11), "cone_w")
    return m, (6, 6)

def fence():
    m = Model(34, 5, 44)
    for px_ in (1.5, 32.5):
        cyl(m, px_, 2.5, 1.2, 0, 42, "fence")
    m.fill((m.x >= 1) & (m.x <= 33) & (np.abs(m.y - 2.5) <= 0.9) & (m.z >= 39.5) & (m.z <= 41), "fence")
    mesh = (m.x > 2.5) & (m.x < 31.5) & (np.abs(m.y - 2.5) <= 0.5) & (m.z >= 1) & (m.z <= 39.5)
    mesh &= ((np.floor(m.x + m.z) % 4 == 0) | (np.floor(m.x - m.z) % 4 == 0))
    m.fill(mesh, "wire")
    return m, (17, 2.5)

PROPS = {
    "fire_hydrant": (hydrant, [0]),
    "streetlight": (streetlight, [0, 1, 2, 3]),
    "palm_tree": (palm, [0]),
    "trash_can": (trash_can, [0]),
    "dumpster": (dumpster, [0, 1]),
    "bus_bench": (bench, [0, 1, 2, 3]),
    "traffic_cone": (cone, [0]),
    "chainlink_fence": (fence, [0, 1]),
}

def rot_anchor(shape, anchor, k):
    """Anchor ground point after np.rot90(k) on axes (0, 1)."""
    X, Y = shape[0], shape[1]
    ax, ay = anchor
    for _ in range(k):
        ax, ay = Y - ay, ax
        X, Y = Y, X
    return ax, ay

# ---------------------------------------------------------------- build
def build(out: Path, car_dir: Path, officer_png: Path):
    out.mkdir(parents=True, exist_ok=True)
    tdir, pdir = out / "tiles", out / "props"
    tdir.mkdir(exist_ok=True); pdir.mkdir(exist_ok=True)
    cols = 8
    atlas = Image.new("RGBA", (TW * cols, TH * math.ceil(len(TILES) / cols)), (0, 0, 0, 0))
    tile_imgs, index = {}, {}
    for i, name in enumerate(TILES):
        im = render_tile(name)
        tile_imgs[name] = im
        im.save(tdir / f"{name}.png")
        atlas.paste(im, ((i % cols) * TW, (i // cols) * TH))
        index[name] = [i % cols, i // cols]
    atlas.save(out / "rampart_street_tiles.png")
    (out / "rampart_street_tiles_index.json").write_text(json.dumps(index, indent=1))
    tres = ['[gd_resource type="TileSet" load_steps=3 format=3]', "",
            '[ext_resource type="Texture2D" path="res://art/tiles/rampart_street_tiles.png" id="1_tiles"]', "",
            '[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_1"]',
            'texture = ExtResource("1_tiles")', "texture_region_size = Vector2i(64, 32)"]
    tres += [f"{c}:{r}/0 = 0" for c, r in index.values()]
    tres += ["", "[resource]", "tile_shape = 1", "tile_layout = 5", "tile_size = Vector2i(64, 32)",
             'sources/0 = SubResource("TileSetAtlasSource_1")', ""]
    (out / "rampart_street_tileset.tres").write_text("\n".join(tres))

    prop_imgs, anchors = {}, {}
    for name, (fn, rots) in PROPS.items():
        base, anc = fn()
        for k in rots:
            mm = base.rotated(k)
            ax, ay = rot_anchor(base.shape, anc, k)
            im, origin = render(mm, PROP_PAL)
            apx = anchor_px(origin, ax, ay)
            fname = name if len(rots) == 1 else f"{name}_r{k}"
            im.save(pdir / f"{fname}.png")
            prop_imgs[fname] = (im, apx)
            anchors[fname] = {"size": im.size, "ground_anchor_px": [round(apx[0], 1), round(apx[1], 1)]}
    (out / "props_anchors.json").write_text(json.dumps(anchors, indent=1))

    car_meta = json.loads((car_dir / "crown_vic_anchors.json").read_text())
    for k, v in car_meta.items():
        prop_imgs["car_" + k] = (Image.open(car_dir / v["file"]), tuple(v["ground_center_px"]))
    officer = Image.open(officer_png).crop((0, 0, 32, 48))
    prop_imgs["officer"] = (officer, (16, 45.5))
    scene(out, tile_imgs, prop_imgs)
    tiles_sheet(out, tile_imgs)

def tiles_sheet(out, tile_imgs):
    S, cols = 3, 8
    names = list(tile_imgs)
    rows = math.ceil(len(names) / cols)
    cw, ch = TW * S + 16, TH * S + 34
    sheet = Image.new("RGB", (cols * cw + 16, rows * ch + 16), (40, 42, 48))
    from PIL import ImageDraw
    d = ImageDraw.Draw(sheet)
    for i, n in enumerate(names):
        x0, y0 = 16 + (i % cols) * cw, 16 + (i // cols) * ch
        big = tile_imgs[n].resize((TW * S, TH * S), Image.NEAREST)
        sheet.paste(big, (x0, y0), big)
        d.text((x0, y0 + TH * S + 4), n, fill=(210, 210, 214))
    sheet.save(out / "rampart_tiles_preview.png")

def scene(out, tiles, props):
    N = 15
    grid = [["sidewalk"] * N for _ in range(N)]
    road = range(6, 11)
    for gx in range(N):
        for gy in range(N):
            in_x, in_y = gy in road, gx in road
            if in_x or in_y:
                grid[gy][gx] = "asphalt"
                if in_x and not in_y:
                    grid[gy][gx] = "double_yellow_x" if gy == 8 else ("lane_dash_x" if gy in (7, 9) and gx % 3 == 0 else "asphalt")
                if in_y and not in_x:
                    grid[gy][gx] = "double_yellow_y" if gx == 8 else ("lane_dash_y" if gx in (7, 9) and gy % 3 == 0 else "asphalt")
    for g in road:
        grid[g][5] = "crosswalk_x"; grid[g][11] = "crosswalk_x"
        grid[5][g] = "crosswalk_y"; grid[11][g] = "crosswalk_y"
    grid[8][3] = "manhole"; grid[7][13] = "asphalt_cracked"; grid[13][9] = "asphalt_patched"
    for gx in range(N):
        if gx not in road:
            grid[5][gx] = "curb_SW" if gx not in (5,) else grid[5][gx]
            grid[11][gx] = "curb_NE" if gx not in (11,) else grid[11][gx]
    for gy in range(N):
        if gy not in road:
            grid[gy][5] = "curb_SE" if gy not in (5,) else grid[gy][5]
            grid[gy][11] = "curb_NW" if gy not in (11,) else grid[gy][11]
    grid[5][5] = grid[5][11] = grid[11][5] = grid[11][11] = "sidewalk"
    grid[5][2] = "curb_red_SW"; grid[5][3] = "curb_red_SW"; grid[11][13] = "storm_drain_NE"
    grid[3][6 - 6 + 13] = "sidewalk_stained"; grid[13][2] = "sidewalk_stained"
    # the Hole: far corner lot
    for gy in range(12, N):
        for gx in range(12, N):
            grid[gy][gx] = ["dirt", "dirt_weeds", "rubble", "rubble_heavy"][(gx * 3 + gy * 5) % 4]
    for gy in range(0, 4):
        for gx in range(0, 4):
            grid[gy][gx] = "parkway_grass"
    for gy in range(0, 5):
        grid[gy][13] = "alley"; grid[gy][14] = "alley"
    ox = N * 32 + 40
    oy = 300
    Wc, Hc = N * 64 + 80, N * 32 + oy + 60
    canvas = Image.new("RGBA", (Wc, Hc), (24, 26, 32, 255))
    for gy in range(N):
        for gx in range(N):
            sx, sy = ox + (gx - gy) * 32 - 32, oy + (gx + gy) * 16
            t = tiles[grid[gy][gx]]
            canvas.paste(t, (sx, sy), t)
    U = 32
    placed = [
        ("palm_tree", 1.5, 4.5), ("palm_tree", 4.5, 1.5), ("palm_tree", 12.2, 4.5), ("palm_tree", 4.5, 13.5),
        ("palm_tree", 14.2, 4.5),
        ("streetlight_r1", 4.6, 4.6), ("streetlight_r3", 11.4, 11.4),
        ("fire_hydrant", 3.2, 5.3), ("bus_bench_r2", 1.9, 4.4), ("trash_can", 12.4, 3.2),
        ("dumpster_r1", 13.6, 1.4),
        ("chainlink_fence_r0", 12.5, 12.1), ("chainlink_fence_r0", 14.5, 12.1),
        ("chainlink_fence_r1", 12.1, 12.5), ("chainlink_fence_r1", 12.1, 13.5), ("chainlink_fence_r1", 12.1, 14.5),
        ("traffic_cone", 13.2, 11.6), ("traffic_cone", 13.9, 11.6),
        ("car_NW", 2.6, 10.25), ("officer", 3.3, 11.45), ("traffic_cone", 4.5, 10.4),
    ]
    order = sorted(placed, key=lambda p: p[1] + p[2])
    for name, gxf, gyf in order:
        im, (axp, ayp) = props[name]
        X, Y = gxf * U, gyf * U
        sx = ox + (X - Y) - axp
        sy = oy + (X + Y) / 2 - ayp
        canvas.paste(im, (int(round(sx)), int(round(sy))), im)
    canvas = canvas.crop(canvas.getbbox())
    canvas.save(out / "rampart_test_scene.png")
    canvas.resize((canvas.width * 2, canvas.height * 2), Image.NEAREST).save(out / "rampart_test_scene_2x.png")

if __name__ == "__main__":
    build(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]))
