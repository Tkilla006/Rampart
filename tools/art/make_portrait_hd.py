"""Detailed 96x96 dialogue portrait for the rookie officer.

Shapes are laid out as material labels, shaded from a single light (upper left)
into color ramps, outlined, then facial features are placed by hand per expression.
Original art. Expressions: neutral, smile, angry, sad, surprised, shaken, tired.
"""
import math
import sys
from pathlib import Path
from PIL import Image, ImageDraw

W = H = 96
CX = 48.0  # face center line falls between pixels 47 and 48; mirror x -> 95 - x

C = {
    "K": (14, 13, 22),
    # skin ramp, light -> dark
    "s5": (238, 194, 154), "s4": (220, 168, 126), "s3": (199, 143, 104),
    "s2": (170, 114, 82), "s1": (134, 84, 61), "s0": (96, 56, 43),
    "pk": (204, 128, 116), "bag": (150, 104, 104),
    # lips, teeth, mouth
    "lp3": (206, 136, 118), "lp2": (178, 106, 92), "lp1": (146, 80, 70), "lpd": (88, 42, 40),
    "T": (236, 230, 220), "T2": (196, 188, 180), "M": (52, 22, 26), "tg": (164, 76, 78),
    # eyes
    "W": (232, 226, 218), "W1": (200, 192, 184), "W2": (168, 160, 154),
    "i1": (58, 36, 24), "i2": (92, 60, 38), "i3": (128, 88, 58), "E": (20, 16, 20), "hl": (250, 250, 248),
    # hair ramp
    "h4": (122, 90, 66), "h3": (88, 63, 46), "h2": (62, 43, 32), "h1": (42, 29, 22), "h0": (24, 16, 13),
    # uniform navy ramp
    "n4": (70, 88, 146), "n3": (48, 62, 112), "n2": (34, 44, 84), "n1": (24, 31, 60), "n0": (14, 18, 38),
    "u0": (18, 18, 26), "u1": (36, 36, 48),
    # metal
    "G4": (250, 232, 160), "G3": (226, 196, 110), "G2": (190, 152, 70), "G1": (138, 104, 44), "G0": (84, 60, 28),
    # patch
    "pb": (196, 164, 84), "pf": (82, 112, 168), "pd": (40, 60, 112),
    # radio mic
    "B0": (20, 20, 24), "B1": (50, 50, 58), "B2": (88, 88, 98),
    "btn": (40, 44, 64), "sw": (190, 226, 246), "sw2": (240, 250, 255),
}
SKIN = ["s0", "s1", "s2", "s3", "s4", "s5"]
DARKER = {"s5": "s4", "s4": "s3", "s3": "s2", "s2": "s1", "s1": "s0", "W": "W1", "W1": "W2",
          "T": "T2", "lp3": "lp2", "lp2": "lp1", "h2": "h1", "h3": "h2"}

L = (-0.35, -0.45, 0.82)
_n = math.sqrt(sum(v * v for v in L))
L = tuple(v / _n for v in L)

def dot(n):
    m = math.sqrt(sum(v * v for v in n)) or 1
    return sum(a * b / m for a, b in zip(n, L))

def band(i, names, cuts):
    for name, cut in zip(names, cuts):
        if i > cut:
            return name
    return names[-1]

def skin_of(i):
    return band(i, ["s5", "s4", "s3", "s2", "s1", "s0"], [0.86, 0.72, 0.5, 0.34, 0.2, -9])

def navy_of(i):
    return band(i, ["n4", "n3", "n2", "n1", "n0"], [0.8, 0.63, 0.45, 0.3, -9])

def hair_of(i):
    return band(i, ["h3", "h2", "h1", "h0"], [0.6, 0.4, 0.2, -9])

def face_hw(y):
    if y < 14 or y > 63:
        return -1
    if y <= 40:
        return 17 * math.sqrt(max(0.0, 1 - ((40 - y) / 26.5) ** 2))
    if y <= 47:
        return 17 - (y - 40) * 0.12
    if y <= 59:
        t = (y - 47) / 12
        return 16.16 - 8.16 * t ** 1.3
    t = (y - 59) / 4.6
    return 8 * math.sqrt(max(0.0, 1 - t * t))

def hairline(x):
    if x < 40:
        return 27.5 - (40 - x) * 0.12
    return 27 + 3.2 * math.exp(-((x - 51) / 7) ** 2)

# material labels
BG, SHIRT, NECK, UNDER, COLL, EAR, FACE, HAIR = range(8)

def layout():
    lab = Image.new("L", (W, H), BG)
    d = ImageDraw.Draw(lab)
    for y in range(66, H):
        hw = 48 if y >= 84 else 11 + 37 * math.sqrt((y - 66) / 18)
        d.line([(round(CX - hw), y), (round(CX + hw) - 1, y)], fill=SHIRT)
    d.polygon([(38, 50), (57, 50), (59, 72), (36, 72)], fill=NECK)
    d.polygon([(41, 70), (54, 70), (48, 88), (47, 88)], fill=UNDER)
    left = [(36, 66), (41, 70), (47, 88), (44, 89), (33, 80), (26, 74)]
    d.polygon(left, fill=COLL)
    d.polygon([(95 - x, y) for x, y in left], fill=COLL)
    d.ellipse([28, 39, 33, 51], fill=EAR)
    d.ellipse([62, 39, 67, 51], fill=EAR)
    g = [[lab.getpixel((x, y)) for x in range(W)] for y in range(H)]
    for y in range(H):
        hw = face_hw(y)
        for x in range(W):
            if hw > 0 and abs(x + 0.5 - CX) <= hw:
                g[y][x] = FACE
    for y in range(10, 47):
        for x in range(W):
            dx, dy = (x + 0.5 - CX) / 19.5, (y + 0.5 - 35.5) / 23
            if dx * dx + dy * dy > 1:
                continue
            hw = face_hw(y)
            on_face = g[y][x] == FACE
            if on_face:
                m = 3 if y < 40 else (1.6 if y < 46 else 0)
                if y < hairline(x) or abs(x + 0.5 - CX) > hw - m:
                    g[y][x] = HAIR
            elif y < 37:
                g[y][x] = HAIR
    return g

def nb(g, x, y):
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nx, ny = x + dx, y + dy
        if 0 <= nx < W and 0 <= ny < H:
            yield nx, ny, g[ny][nx]

def shade(g):
    out = [[None] * W for _ in range(H)]
    jaw_bottom = {}
    for y in range(H):
        for x in range(W):
            if g[y][x] == FACE:
                jaw_bottom[x] = y
    for y in range(H):
        for x in range(W):
            m = g[y][x]
            px = x + 0.5 - CX
            if m == FACE:
                hw = max(face_hw(y), 1)
                dx, dy = px / hw, (y - 42) / 30
                if dy > 0:
                    dy *= 0.55
                dx = max(-1.0, min(1.0, dx)) * (0.85 if y > 50 else 1.0)
                nz = math.sqrt(max(0.05, 1 - 0.8 * dx * dx - dy * dy))
                i = dot((dx * 0.95, dy, nz))
                # sculpting: brow ridge / eye sockets, nose, cheeks, under nose
                for ex in (40.5, 54.5):
                    r = ((x + 0.5 - ex) / 7) ** 2 + ((y + 0.5 - 41.5) / 4) ** 2
                    if r < 1:
                        i -= 0.1 * (1 - r)
                if 49 <= x <= 51 and 44 <= y <= 53:
                    i -= 0.18
                if 44 <= x <= 51 and 54 <= y <= 55:
                    i -= 0.14
                if ((x - 37) / 4) ** 2 + ((y - 50) / 3) ** 2 < 1:
                    i += 0.08
                if ((x - 60) / 4) ** 2 + ((y - 55) / 3) ** 2 < 1:
                    i -= 0.08
                out[y][x] = skin_of(i + 0.06)
            elif m == EAR:
                i = 0.62 if x < CX else 0.38
                out[y][x] = skin_of(i)
            elif m == NECK:
                i = 0.66 - 0.26 * (px / 10.5)
                jb = jaw_bottom.get(x)
                if jb is not None and y - jb < 7:
                    i -= 0.2
                out[y][x] = skin_of(i)
            elif m == HAIR:
                dx, dy = px / 19.5, (y + 0.5 - 35.5) / 23
                nz = math.sqrt(max(0.05, 1 - dx * dx - dy * dy))
                i = dot((dx, dy, nz))
                t = (x - 40) * 0.55 - y * 0.25 if x >= 40 else (40 - x) * 0.55 - y * 0.25
                i += 0.11 * math.sin(t * 1.15) + 0.04 * math.sin(y * 0.9 + x * 0.3)
                if any(v == BG for _, _, v in nb(g, x, y)):
                    i -= 0.1
                c = hair_of(i)
                if i > 0.7 and math.sin(t * 1.15) > 0.55:
                    c = "h4"
                out[y][x] = c
            elif m in (SHIRT, COLL):
                i = (0.74 if m == COLL else 0.58) - (0.25 if m == COLL else 0.28) * (px / 48)
                if m == SHIRT:
                    if y > 0 and g[y - 1][x] in (BG,) or (y > 1 and g[y - 2][x] == BG):
                        i += 0.18
                    if x < 2 or x > W - 3:
                        i -= 0.1
                out[y][x] = navy_of(i)
            elif m == UNDER:
                out[y][x] = "u1" if x < 46 and y < 76 else "u0"
    # selective internal lines
    final = [row[:] for row in out]
    for y in range(H):
        for x in range(W):
            m = g[y][x]
            ns = list(nb(g, x, y))
            if m == FACE and y + 1 < H and g[y + 1][x] in (NECK, COLL, UNDER, SHIRT):
                final[y][x] = "s0"
            elif m == EAR and any(v == FACE for _, _, v in ns):
                final[y][x] = "s1"
            elif m == COLL and any(v in (SHIRT, UNDER, NECK) for _, _, v in ns):
                final[y][x] = "n0"
            elif m == NECK and any(v in (COLL, UNDER) for _, _, v in ns):
                final[y][x] = "s1"
            elif m == HAIR and any(v == FACE for _, _, v in ns) and final[y][x] in ("h0", "h1"):
                final[y][x] = "h2" if x < CX else "h1"
    # silhouette outline
    for y in range(H):
        for x in range(W):
            if g[y][x] == BG and any(v != BG for _, _, v in nb(g, x, y)):
                final[y][x] = "K"
    return final

class Art:
    def __init__(self, px):
        self.p = px

    def set(self, x, y, c):
        if 0 <= x < W and 0 <= y < H and c:
            self.p[y][x] = c

    def F(self, x, y, c, mirror=True):
        """Feature pixel on the lit side, mirrored one shade darker on the far side."""
        self.set(x, y, c)
        if mirror:
            self.set(95 - x, y, DARKER.get(c, c))

    def row(self, y, x_from, c):
        """Symmetric horizontal run from x_from to the center line."""
        for x in range(x_from, 48):
            self.F(x, y, c)

    def get(self, x, y):
        return self.p[y][x]

def uniform(a):
    # placket and buttons
    for y in range(89, H):
        a.set(46, y, "n1"); a.set(49, y, "n3"); a.set(47, y, "n2"); a.set(48, y, "n2")
    for by in (92,):
        a.set(47, by, "btn"); a.set(48, by, "btn"); a.set(47, by - 1, "B2")
    # armpit folds
    for i in range(9):
        a.set(12 + i, 95 - i, "n1"); a.set(13 + i, 95 - i, "n3")
        a.set(83 - i, 95 - i, "n0")
    for i in range(6):
        a.set(16 + i, 84 + i // 2, "n1")
    # shoulder patches (cut by the frame)
    for side in (0, 1):
        for y in range(79, 96):
            for x in range(0, 9):
                xx = x if side == 0 else 95 - x
                edge = y in (79, 95) or x == 8
                if y == 79 and x in (7, 8):
                    continue
                a.set(xx, y, "pb" if edge else ("pd" if 4 <= x <= 6 and 84 <= y <= 90 else "pf"))
        a.set(5 if side == 0 else 90, 87, "pb")
    # nameplate (officer's right chest) and pocket flap
    for x in range(24, 38):
        a.set(x, 85, "G4"); a.set(x, 86, "G3"); a.set(x, 87, "G3"); a.set(x, 88, "G1")
    for x in (26, 27, 29, 31, 32, 34, 35):
        a.set(x, 87, "G0")
    a.set(23, 85, "K"); a.set(38, 85, "K")
    for x in range(22, 41):
        a.set(x, 91, "n0"); a.set(x, 92, "n3"); a.set(x, 93, "n2"); a.set(x, 94, "n0")
    a.set(31, 93, "btn"); a.set(31, 92, "B2")
    # badge (officer's left chest): oval shield with crest
    bx, by = 64, 88
    for y in range(80, 96):
        for x in range(57, 72):
            dx, dy = (x + 0.5 - bx) / 5.5, (y + 0.5 - by) / 6.5
            crest = 80 <= y <= 82 and abs(x + 0.5 - bx) <= 2.5
            r = dx * dx + dy * dy
            if r <= 1 or crest:
                nz = math.sqrt(max(0.05, 1 - min(r, 0.95)))
                i = dot((dx, dy, nz))
                c = band(i, ["G4", "G3", "G2", "G1"], [0.85, 0.6, 0.35, -9])
                if 0.32 < r < 0.5:
                    c = "G1"
                if r < 0.12:
                    c = "G3" if (x + y) % 2 else "G2"
                a.set(x, y, c)
            elif r <= 1.35 or (79 <= y <= 83 and abs(x + 0.5 - bx) <= 3.5):
                if a.get(x, y) and a.get(x, y).startswith("n"):
                    a.set(x, y, "K")
    a.set(63, 87, "G4")
    # shoulder radio mic and coiled cord
    for y in range(74, 82):
        for x in range(70, 76):
            a.set(x, y, "B0")
    for x in range(70, 76):
        a.set(x, 73, "K"); a.set(x, 82, "K")
    for y in range(74, 82):
        a.set(69, y, "K"); a.set(76, y, "K")
    a.set(70, 74, "B2"); a.set(71, 74, "B1")
    for x in (71, 73):
        for y in (76, 78, 80):
            a.set(x, y, "B2")
    for y in range(83, 96):
        a.set(73, y, "B0" if y % 2 else "B2"); a.set(74, y, "B0")

def nose(a):
    for y in range(44, 51):
        a.set(45, y, "s4")
    for y in range(45, 52):
        a.set(49, y, "s2")
    for y in range(48, 52):
        a.set(50, y, "s2")
    a.set(46, 51, "s5"); a.set(47, 51, "s4")
    a.set(43, 52, "s2"); a.set(44, 53, "s1"); a.set(52, 52, "s1"); a.set(51, 53, "s0")
    a.set(45, 53, "s0"); a.set(46, 53, "s1"); a.set(49, 53, "s1"); a.set(50, 53, "s0")
    for x in range(45, 51):
        a.set(x, 54, "s2")

def ears(a):
    for x, y in ((30, 42), (29, 43), (29, 44), (29, 45), (29, 46), (29, 47), (30, 48), (31, 49)):
        a.F(x, y, "s1")
    for y in range(44, 48):
        a.F(31, y, "s2")

# ---- expression parts --------------------------------------------------
BROW = {  # (outer_y, peak_y, inner_y) for the brow's top edge
    "neutral": (38, 36, 37), "smile": (37, 35, 36), "angry": (36, 37, 39), "sad": (38, 35, 34),
    "surprised": (34, 32, 33), "shaken": (36, 34, 34), "tired": (38, 37, 38),
}

def brows(a, kind):
    o, p, i = BROW[kind]
    for x in range(35, 45):
        if x <= 39:
            yt = o + (p - o) * (x - 35) / 4
        else:
            yt = p + (i - p) * (x - 39) / 5
        yt = round(yt)
        thick = 2 if x in (35, 36) else 3
        for k in range(thick):
            a.F(x, yt + k, "h2" if k == 0 else ("h0" if x >= 42 and k == thick - 1 else "h1"))
    if kind == "angry":
        for y in range(37, 41):
            a.set(46, y, "s1"); a.set(49, y, "s1")
    if kind in ("sad", "shaken"):
        a.row(32, 44, "s2")
    if kind == "surprised":
        for x in range(40, 48):
            if x % 3:
                a.F(x, 29, "s2")
        for x in range(42, 48):
            a.F(x, 31, "s2")

# eye shapes on the viewer-left eye; mirrored for the right
def lid(a, pts, c="E"):
    for x, y in pts:
        a.F(x, y, c)

def whites(a, rows):
    for y, x0, x1 in rows:
        for x in range(x0, x1 + 1):
            a.F(x, y, "W1" if y == rows[0][0] else "W")

def iris(a, cx, top, pin=False):
    """4x4 iris, painted only where white is showing. Highlight stays on the lit side."""
    pat = [["i2", "i1", "i1", "i2"],
           ["hl", "E", "E", "i1"],
           ["i2", "E", "E", "i2"],
           ["i3", "i2", "i2", "i3"]]
    if pin:
        pat = [["i2", "i3", "i3", "i2"],
               ["i3", "E", "i3", "i3"],
               ["i2", "i3", "i3", "i2"],
               ["i3", "i2", "i2", "i3"]]
    for r in range(4):
        for k in range(4):
            x, y = cx + k, top + r
            if a.get(x, y) in ("W", "W1", "W2"):
                a.set(x, y, pat[r][k])

def eyes(a, kind):
    gaze_y = 0
    if kind in ("neutral", "surprised", "shaken"):
        top = 41 if kind == "neutral" else 40
        a.F(38, top - 2, "s2"); a.F(39, top - 2, "s2"); a.F(40, top - 2, "s2"); a.F(41, top - 2, "s2"); a.F(42, top - 2, "s2")
        lid(a, [(x, top) for x in range(37, 44)] + [(36, top + 1)])
        rows = [(top + 1, 37, 43), (top + 2, 37, 43), (top + 3, 38, 42)]
        if kind != "neutral":
            rows.append((top + 4, 38, 42))
        whites(a, rows)
        low = rows[-1][0] + 1
        for x in range(38, 43):
            a.F(x, low, "s2")
        it = top + (1 if kind == "neutral" else 2)
        iris(a, 39, it, pin=(kind == "shaken"))
        iris(a, 53, it, pin=(kind == "shaken"))
        a.F(44, top + 2, "pk")
        if kind == "shaken":
            for x in range(37, 44):
                a.F(x, low + 1, "bag")
    elif kind == "smile":
        lid(a, [(37, 43), (38, 42), (39, 42), (40, 42), (41, 42), (42, 42), (43, 43)])
        whites(a, [(43, 38, 42)])
        iris(a, 39, 42)
        iris(a, 53, 42)
        for x in range(38, 43):
            a.F(x, 44, "s2")
        for x in range(36, 42):
            a.F(x, 46, "s4")
        a.F(44, 43, "pk")
    elif kind == "angry":
        lid(a, [(36, 41), (37, 41), (38, 42), (39, 42), (40, 42), (41, 42), (42, 43), (43, 43)])
        whites(a, [(43, 37, 41), (44, 38, 42)])
        iris(a, 39, 42)
        iris(a, 53, 42)
        for x in range(38, 43):
            a.F(x, 45, "s1")
        a.F(44, 44, "pk")
    elif kind == "sad":
        lid(a, [(36, 43), (37, 42), (38, 41), (39, 41), (40, 41), (41, 41), (42, 41), (43, 41)])
        whites(a, [(42, 38, 43), (43, 37, 43), (44, 38, 42)])
        iris(a, 39, 43)
        iris(a, 53, 43)
        for x in range(38, 43):
            a.F(x, 45, "s2")
        a.F(44, 43, "pk")
    elif kind == "tired":
        for x in range(37, 44):
            a.F(x, 41, "s2"); a.F(x, 42, "s2")
        lid(a, [(x, 43) for x in range(37, 44)] + [(36, 43)])
        whites(a, [(44, 38, 42)])
        iris(a, 39, 43)
        iris(a, 53, 43)
        for x in range(38, 43):
            a.F(x, 45, "s2")
        for x in range(37, 44):
            a.F(x, 46, "bag"); a.F(x, 47, "s2") if x % 2 else None
        a.F(44, 44, "pk")

def mouth(a, kind):
    if kind == "smile":
        a.F(40, 55, "s1"); a.F(41, 56, "lpd")
        a.row(56, 42, "lp1")
        a.F(42, 57, "lpd"); a.row(57, 43, "T")
        a.F(43, 58, "lpd"); a.row(58, 44, "T2")
        a.row(59, 44, "lpd")
        a.row(60, 45, "lp2"); a.F(46, 60, "lp3")
        a.row(61, 45, "s2")
        a.F(45, 57, "T2")
        for x, y in ((40, 51), (39, 52), (39, 53), (39, 54)):
            a.F(x, y, "s2")
    elif kind == "angry":
        a.row(57, 42, "lp1")
        a.F(42, 58, "lpd"); a.row(58, 43, "T")
        a.F(45, 58, "T2"); a.F(47, 58, "T2")
        a.row(59, 42, "lpd")
        a.F(41, 60, "lpd")
        a.row(60, 44, "lp2")
        a.row(61, 45, "s2")
        for x, y in ((41, 52), (40, 53), (40, 54)):
            a.F(x, y, "s2")
        a.F(43, 53, "s0")
    elif kind == "sad":
        a.row(57, 44, "lp1")
        a.row(58, 43, "lpd"); a.F(42, 59, "lpd")
        a.row(59, 44, "lp2"); a.F(46, 59, "lp3")
        a.row(60, 45, "lp2")
        a.row(61, 45, "s2")
        a.F(47, 62, "s2")
    elif kind == "surprised":
        a.row(56, 44, "lp1")
        a.F(43, 57, "lp1"); a.row(57, 44, "T")
        a.F(43, 58, "lpd"); a.row(58, 44, "M")
        a.F(43, 59, "lpd"); a.row(59, 44, "M")
        a.F(43, 60, "lpd"); a.row(60, 44, "tg")
        a.row(61, 44, "lp2"); a.F(46, 61, "lp3")
        a.row(62, 45, "s2")
    elif kind == "shaken":
        a.row(57, 43, "lp1")
        a.F(43, 58, "lpd"); a.row(58, 44, "M")
        a.row(59, 44, "lp2"); a.F(46, 59, "M")
        a.row(60, 45, "lp2")
        a.row(61, 45, "s2")
        for x, y, c in ((60, 29, "sw2"), (60, 30, "sw"), (59, 31, "sw"), (60, 31, "sw"), (61, 31, "sw"),
                        (60, 32, "sw"), (65, 37, "sw2"), (65, 38, "sw"), (64, 39, "sw"), (65, 39, "sw"),
                        (66, 39, "sw"), (65, 40, "sw")):
            a.set(x, y, c)
    else:  # neutral, tired
        a.row(57, 43, "lp1"); a.F(47, 56, "lp1")
        a.F(41, 58, "s1"); a.row(58, 42, "lpd")
        a.row(59, 44, "lp2"); a.F(46, 59, "lp3"); a.F(47, 59, "lp3")
        a.row(60, 45, "lp2")
        a.row(61, 45, "s2")
        if kind == "tired":
            a.F(42, 59, "s1")
    if kind not in ("smile",):
        a.F(46, 63, "s4") if False else None

def stubble(a, g):
    for y in range(51, 64):
        for x in range(W):
            if g[y][x] != FACE:
                continue
            c = a.get(x, y)
            if c in SKIN and (x * 7 + y * 3) % 5 < 2 and not (43 <= x <= 52 and 56 <= y <= 61) \
                    and not (43 <= x <= 52 and 51 <= y <= 54):
                a.set(x, y, SKIN[max(0, SKIN.index(c) - 1)])

def palette_for(kind):
    pal = dict(C)
    if kind == "shaken":
        for k in SKIN + ["lp1", "lp2", "lp3", "pk"]:
            r, g, b = pal[k]
            avg = (r + g + b) / 3
            pal[k] = (int(r * 0.7 + avg * 0.3 - 2), int(g * 0.7 + avg * 0.3 + 6), int(b * 0.7 + avg * 0.3 + 8))
    return pal

EXPRESSIONS = ["neutral", "smile", "angry", "sad", "surprised", "shaken", "tired"]

def portrait(kind):
    g = layout()
    a = Art(shade(g))
    uniform(a)
    ears(a)
    nose(a)
    brows(a, kind)
    eyes(a, kind)
    mouth(a, kind)
    if kind == "tired":
        stubble(a, g)
    pal = palette_for(kind)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for y in range(H):
        for x in range(W):
            c = a.p[y][x]
            if c:
                img.putpixel((x, y), pal[c] + (255,))
    return img

def build(out: Path):
    out.mkdir(parents=True, exist_ok=True)
    imgs = [portrait(k) for k in EXPRESSIONS]
    strip = Image.new("RGBA", (W * len(imgs), H), (0, 0, 0, 0))
    for i, (k, im) in enumerate(zip(EXPRESSIONS, imgs)):
        im.save(out / f"rookie_portrait_{k}.png")
        strip.paste(im, (i * W, 0))
    strip.save(out / "rookie_portraits.png")

    def sheet(images, labels, scale, path):
        gap, top = 12, 28
        cell = W * scale
        prev = Image.new("RGB", (len(images) * (cell + gap) + gap, cell + top + gap), (150, 152, 158))
        d = ImageDraw.Draw(prev)
        for i, (lab, im) in enumerate(zip(labels, images)):
            x0 = gap + i * (cell + gap)
            d.rectangle([x0, top, x0 + cell - 1, top + cell - 1], fill=(118, 122, 130))
            big = im.resize((cell, cell), Image.NEAREST)
            prev.paste(big, (x0, top), big)
            d.text((x0 + 4, 8), lab, fill=(20, 20, 24))
        prev.save(path)

    sheet(imgs[:4], EXPRESSIONS[:4], 4, out / "rookie_portraits_preview_1.png")
    sheet(imgs[4:], EXPRESSIONS[4:], 4, out / "rookie_portraits_preview_2.png")
    sheet([imgs[0]], ["neutral, close-up"], 7, out / "rookie_portrait_closeup.png")

if __name__ == "__main__":
    build(Path(sys.argv[1]))
