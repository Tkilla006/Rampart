"""Tiny isometric voxel renderer (2:1 pixel isometric, light from the upper left).

World axes: +x runs down-right on screen, +y runs down-left, +z is up.
Screen mapping: u = x - y, v = (x + y) / 2 - z. 1 voxel = 1 pixel of height = 1/22 m.
"""
import numpy as np
from PIL import Image

class Model:
    def __init__(self, X, Y, Z):
        self.shape = (X, Y, Z)
        self.occ = np.zeros(self.shape, bool)
        self.col = np.zeros(self.shape, np.int16)
        self.keys = [None]
        x, y, z = np.indices(self.shape).astype(float) + 0.5
        self.x, self.y, self.z = x, y, z

    def key(self, k):
        if k not in self.keys:
            self.keys.append(k)
        return self.keys.index(k)

    def fill(self, mask, k):
        self.occ |= mask
        self.col[mask] = self.key(k)

    def paint(self, mask, k):
        """Recolor voxels that already exist."""
        m = mask & self.occ
        self.col[m] = self.key(k)

    def carve(self, mask):
        self.occ &= ~mask
        self.col[mask] = 0

    def rotated(self, k):
        r = Model.__new__(Model)
        r.occ = np.rot90(self.occ, k, axes=(0, 1)).copy()
        r.col = np.rot90(self.col, k, axes=(0, 1)).copy()
        r.keys = self.keys
        r.shape = r.occ.shape
        return r

# per material: base RGB, and optional explicit tones for (top, left-facing +y, right-facing +x)
def tones(rgb, top=1.0, left=0.84, right=0.66, add_top=0):
    t = lambda f, a=0: tuple(min(255, int(c * f + a)) for c in rgb)
    return (t(top, add_top), t(left), t(right))

def render(model, palette, shadow=True, step=0.5, highlight=None, outline=(12, 12, 16)):
    X, Y, Z = model.shape
    umin, umax = -Y, X
    vmin, vmax = -Z, int(np.ceil((X + Y) / 2)) + 1
    Wd, Ht = umax - umin, vmax - vmin
    py, px = np.mgrid[0:Ht, 0:Wd]
    U = (px + umin + 0.5).ravel()
    V = (py + vmin + 0.5).ravel()
    n = U.size
    hit = np.zeros(n, np.int16)
    nrm = np.zeros(n, np.int8)           # 0 top, 1 +y (left face), 2 +x (right face)
    hx = np.zeros(n, np.int32); hy = np.zeros(n, np.int32); hz = np.zeros(n, np.int32)
    t_hi = np.minimum.reduce([2 * (V + Z), 2 * X - U, 2 * Y + U])
    t_lo = np.maximum.reduce([2 * V, -U, U])
    T0 = t_hi.max()
    T1 = t_lo.min()
    px_prev = np.full(n, 10 ** 6); py_prev = np.full(n, 10 ** 6); pz_prev = np.full(n, 10 ** 6)
    active = t_hi > t_lo
    t = T0
    while t >= T1:
        sel = active & (hit == 0)
        if not sel.any():
            break
        ix = np.floor((t + U) / 2).astype(int)
        iy = np.floor((t - U) / 2).astype(int)
        iz = np.floor(t / 2 - V).astype(int)
        inb = sel & (ix >= 0) & (ix < X) & (iy >= 0) & (iy < Y) & (iz >= 0) & (iz < Z)
        if inb.any():
            idx = np.where(inb)[0]
            occ = model.occ[ix[idx], iy[idx], iz[idx]]
            h = idx[occ]
            if h.size:
                hit[h] = model.col[ix[h], iy[h], iz[h]]
                dz = iz[h] != pz_prev[h]
                dxx = ix[h] != px_prev[h]
                nrm[h] = np.where(dz, 0, np.where(dxx, 2, 1))
                hx[h], hy[h], hz[h] = ix[h], iy[h], iz[h]
        px_prev, py_prev, pz_prev = np.where(sel, ix, px_prev), np.where(sel, iy, py_prev), np.where(sel, iz, pz_prev)
        t -= step
    img = np.zeros((n, 4), np.uint8)
    for ki in np.unique(hit):
        if ki == 0:
            continue
        k = model.keys[ki]
        tn = palette[k]
        for f in range(3):
            m = (hit == ki) & (nrm == f)
            img[m, :3] = tn[f]
            img[m, 3] = 255
        if highlight and k in highlight:
            fn, hk = highlight[k]
            m = (hit == ki) & fn(hx, hy, hz)
            for f in range(3):
                mm = m & (nrm == f)
                img[mm, :3] = palette[hk][f]
    if shadow:
        foot = model.occ[:, :, :12].any(axis=2)   # contact shadow from the base only
        from scipy.ndimage import binary_dilation
        foot = binary_dilation(foot, iterations=2)
        gx = np.floor((2 * V + U) / 2).astype(int)
        gy = np.floor((2 * V - U) / 2).astype(int)
        ok = (hit == 0) & (gx >= 0) & (gx < X) & (gy >= 0) & (gy < Y)
        ok[ok] = foot[gx[ok], gy[ok]]
        img[ok] = (10, 10, 18, 92)
    img = img.reshape(Ht, Wd, 4)
    solid = img[:, :, 3] == 255
    if outline:
        edge = np.zeros_like(solid)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            edge |= np.roll(solid, (dy, dx), axis=(0, 1))
        edge &= ~solid
        img[edge] = outline + (255,)
    im = Image.fromarray(img, "RGBA")
    bbox = im.getbbox()
    im = im.crop(bbox)
    return im, (umin + bbox[0], vmin + bbox[1])

def anchor_px(origin, ax, ay):
    """Pixel inside the cropped sprite where world ground point (ax, ay, 0) lands."""
    u0, v0 = origin
    return (ax - ay) - u0, (ax + ay) / 2 - v0
