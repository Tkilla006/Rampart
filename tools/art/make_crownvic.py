"""LAPD Ford Crown Victoria Police Interceptor (2010), voxel model rendered in 4 isometric facings.

Real-world size at 22 voxels per meter: length ~5.4 m, width ~2.0 m, height ~1.45 m.
LAPD 2010 livery: black body with white doors and roof, red/blue light bar, push bar.
Model front points to -x; on screen the car's left (driver) side is at high y.
"""
import json
import sys
from pathlib import Path
import numpy as np
from voxel import Model, render, tones, anchor_px

FONT = {
    "P": ["111", "101", "111", "100", "100"], "O": ["111", "101", "101", "101", "111"],
    "L": ["100", "100", "100", "100", "111"], "I": ["111", "010", "010", "010", "111"],
    "C": ["111", "100", "100", "100", "111"], "E": ["111", "100", "110", "100", "111"],
    "2": ["111", "001", "111", "100", "111"], "A": ["010", "101", "111", "101", "101"],
    "4": ["101", "101", "111", "001", "001"], "3": ["111", "001", "111", "001", "111"],
}

PAL = {
    "blk": ((64, 68, 80), (38, 40, 48), (26, 27, 33)),
    "wht": tones((230, 231, 234), 1.0, 0.88, 0.7),
    "seam": tones((70, 72, 78)),
    "glass": ((70, 86, 104), (40, 50, 64), (30, 38, 50)),
    "glass_hl": ((150, 170, 190), (98, 116, 136), (74, 90, 108)),
    "tire": tones((34, 34, 36)),
    "rim": tones((128, 130, 136)),
    "cap": tones((70, 72, 78)),
    "chrome": tones((190, 192, 198)),
    "bump": tones((44, 45, 50)),
    "push": tones((30, 30, 34)),
    "red": ((255, 70, 64), (220, 40, 40), (170, 26, 30)),
    "blue": ((84, 132, 255), (44, 84, 230), (30, 58, 170)),
    "lbw": tones((240, 240, 236)),
    "lbbase": tones((36, 36, 40)),
    "hl": tones((250, 244, 210)),
    "amber": tones((244, 156, 44)),
    "tail": tones((196, 34, 34)),
    "grille": tones((56, 58, 64)),
    "text": tones((22, 24, 32)),
    "sealg": tones((214, 182, 84)),
    "sealb": tones((44, 74, 150)),
    "plate": tones((232, 232, 222)),
}

def build_model():
    m = Model(124, 46, 36)
    x, y, z = m.x, m.y, m.z
    ay = np.abs(y - 23.0)                       # distance from the center line
    # lower body with a side profile: hood, beltline, trunk
    top = np.interp(x, [4, 7, 44, 92, 93, 119, 122], [16, 18.4, 19, 19, 20, 20, 17])
    body = (x >= 4) & (x <= 122) & (ay <= 22) & (z >= 4) & (z <= top)
    fc = (x < 8) & (ay > 18) & (((8 - x) ** 2 + (ay - 18) ** 2) > 16)     # rounded front corners
    rc = (x > 119) & (ay > 19) & (((x - 119) ** 2 + (ay - 19) ** 2) > 9)  # rounded rear corners
    tuck = (z < 6) & (ay > 21)
    body &= ~(fc | rc | tuck)
    m.fill(body, "blk")
    for ax in (28, 92):                                                    # wheel arches
        m.carve(((x - ax) ** 2 + (z - 7.7) ** 2 < 9.6 ** 2) & (ay > 12))
    # wheels
    for ax in (28, 92):
        r2 = (x - ax) ** 2 + (z - 7.7) ** 2
        tire = (r2 <= 7.7 ** 2) & (ay >= 13.5) & (ay <= 19.5)
        m.fill(tire, "tire")
        m.paint(tire & (ay >= 18.5) & (r2 <= 4.6 ** 2), "rim")
        m.paint(tire & (ay >= 18.5) & (r2 <= 1.7 ** 2), "cap")
    # greenhouse: windshield, roof, rear window, with tumblehome
    xf = 44 + (z - 19) * 1.0
    xr = 92 - (z - 19) * (10 / 12)
    hwc = 20.5 - (z - 19) * 0.33
    cab = (z >= 19) & (z <= 31.5) & (x >= xf) & (x <= xr) & (ay <= hwc)
    m.fill(cab, "wht")
    win_z = (z >= 20.5) & (z <= 30)
    m.paint(cab & win_z & (ay <= hwc - 1.6) & (x - xf >= 1.6) & (xr - x >= 1.6), "glass")
    m.paint(cab & win_z & (x - xf < 1.6) & (ay <= hwc - 2), "glass")
    m.paint(cab & win_z & (xr - x < 1.6) & (ay <= hwc - 2), "glass")
    side = cab & (ay > hwc - 1.6) & (z >= 20.5) & (z <= 29.5)
    m.paint(side & (((x > xf + 2.5) & (x < 65)) | ((x > 68) & (x < xr - 2.5))), "glass")
    # doors white, seams, handles
    sidel = (ay > 21) & (z >= 4.5) & (z <= 19.5)
    m.paint(sidel & (x >= 44) & (x <= 86), "wht")
    for sx in (44.5, 65, 86):
        m.paint(sidel & (np.abs(x - sx) < 0.6) & (z >= 5), "seam")
    m.paint(sidel & (z >= 15) & (z <= 16) & ((np.abs(x - 60) < 1.2) | (np.abs(x - 81) < 1.2)), "chrome")
    # front-door seal and POLICE lettering, reading front-to-back on the left side, back-to-front on the right
    seal = sidel & ((x - 51) ** 2 + (z - 13) ** 2 <= 3.6 ** 2) & (x < 64)
    m.paint(seal, "sealg")
    m.paint(sidel & ((x - 51) ** 2 + (z - 13) ** 2 <= 2.2 ** 2), "sealb")
    word = "POLICE"
    for side_sign in (-1, 1):
        surf = (ay > 21) & ((y - 23.0) * side_sign > 0)
        for i, ch in enumerate(word):
            for r, rowbits in enumerate(FONT[ch]):
                for c, bit in enumerate(rowbits):
                    if bit != "1":
                        continue
                    off = i * 4 + c
                    gx = 84 - off if side_sign < 0 else 60 + off
                    gz = 11 - r
                    m.paint(surf & (np.floor(x) == gx) & (np.floor(z) == gz), "text")
    # roof number for the air unit
    roof = cab & (z >= 30.5)
    for i, ch in enumerate("2A43"):
        for r, rowbits in enumerate(FONT[ch]):
            for c, bit in enumerate(rowbits):
                if bit == "1":
                    gx = 67 + i * 4 + c
                    m.paint(roof & (np.floor(x) == gx) & (np.floor(y) >= 18 + r * 2) & (np.floor(y) <= 19 + r * 2), "text")
    # light bar: red driver side, blue passenger side
    lb = (x >= 57) & (x <= 62) & (y >= 7) & (y <= 39) & (z >= 31) & (z <= 34)
    m.fill(lb, "lbbase")
    lens = lb & (z >= 32.2)
    m.paint(lens & (y > 24.5), "red")
    m.paint(lens & (y < 21.5), "blue")
    m.paint(lens & (y >= 21.5) & (y <= 24.5), "lbw")
    # A-pillar spotlight (driver side), mirrors
    m.fill((x >= 45) & (x <= 48) & (y >= 43) & (y <= 45) & (z >= 21) & (z <= 23.5), "chrome")
    m.fill((x >= 46) & (x <= 49) & ((y <= 1.2) | (y >= 44.8)) & (z >= 19) & (z <= 21.5), "blk")
    # front: push bar, bumper, headlights, grille
    pb = (x <= 4) & (x >= 0.5) & (ay <= 12.5) & (z >= 6) & (z <= 17)
    pb &= (np.abs(ay - 11) < 1.5) | (np.abs(z - 8.5) < 1.1) | (np.abs(z - 15.5) < 1.1)
    m.fill(pb, "push")
    m.paint((x <= 6.5) & (z >= 4) & (z <= 10), "bump")
    front = (x <= 6.5) & (z > 10) & (z <= 15.5)
    m.paint(front & (ay >= 9) & (ay <= 19), "hl")
    m.paint(front & (ay < 8), "grille")
    m.paint(front & (ay < 8) & (np.floor(z) % 2 == 0), "chrome")
    m.paint((x <= 6.5) & (z > 9) & (z <= 10.8) & (ay >= 14) & (ay <= 19), "amber")
    # rear: bumper, tail lights, plate
    rear = x >= 120.5
    m.paint(rear & (z >= 4) & (z <= 11), "bump")
    m.paint(rear & (z >= 13) & (z <= 18) & (ay >= 9) & (ay <= 20), "tail")
    m.paint(rear & (z >= 13) & (z <= 18) & (ay >= 9) & (ay <= 10.6), "lbw")
    m.paint(rear & (z >= 8.5) & (z <= 12) & (ay < 4), "plate")
    # trunk antenna
    m.fill((np.floor(x) == 104) & (np.floor(y) == 23) & (z >= 20) & (z <= 30), "blk")
    return m

def facing(model):
    """Screen heading of the car's front, from the push bar position."""
    ki = model.keys.index("push")
    px_, py_, _ = np.nonzero(model.col == ki)
    ox, oy, _ = np.nonzero(model.occ)
    fx, fy = px_.mean() - ox.mean(), py_.mean() - oy.mean()
    du, dv = fx - fy, (fx + fy) / 2
    return ("N" if dv < 0 else "S") + ("W" if du < 0 else "E")

GLASS_HL = {"glass": (lambda X, Y, Z: ((X + Y + 2 * Z) % 23) < 2, "glass_hl")}

def build(out: Path):
    out.mkdir(parents=True, exist_ok=True)
    base = build_model()
    meta = {}
    for k in range(4):
        mm = base.rotated(k)
        name = facing(mm)
        im, origin = render(mm, PAL, highlight=GLASS_HL)
        X, Y, _ = mm.shape
        ax, ay = anchor_px(origin, X / 2, Y / 2)
        im.save(out / f"crown_vic_{name}.png")
        meta[name] = {"file": f"crown_vic_{name}.png", "size": im.size,
                      "ground_center_px": [round(ax, 1), round(ay, 1)]}
    (out / "crown_vic_anchors.json").write_text(json.dumps(meta, indent=2))
    return meta

if __name__ == "__main__":
    print(build(Path(sys.argv[1])))
