# Quality DXT5 (BC3) encoder: colour bleed into transparent pixels, PCA endpoints
# with least-squares refinement, alpha block picks the better of 8- and 6-level modes.
import numpy as np, struct

def bleed(rgba, passes=8):
    a = rgba[..., 3].astype(np.float32)
    rgb = rgba[..., :3].astype(np.float32)
    known = a > 0
    out = rgb.copy()
    for _ in range(passes):
        if known.all(): break
        acc = np.zeros_like(out); cnt = np.zeros(a.shape, np.float32)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0: continue
                k = np.roll(np.roll(known, dy, 0), dx, 1)
                c = np.roll(np.roll(out, dy, 0), dx, 1)
                acc += c * k[..., None]; cnt += k
        grow = (~known) & (cnt > 0)
        out[grow] = acc[grow] / cnt[grow][:, None]
        known = known | grow
    res = rgba.copy(); res[..., :3] = np.clip(out + 0.5, 0, 255).astype(np.uint8)
    return res

def to565(c):
    r, g, b = [int(round(max(0, min(255, v)))) for v in c]
    return ((r * 31 + 127) // 255) << 11 | ((g * 63 + 127) // 255) << 5 | ((b * 31 + 127) // 255)

def from565(v):
    r = (v >> 11) & 31; g = (v >> 5) & 63; b = v & 31
    return np.array([(r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)], np.float32)

def palette(c0, c1):
    a, b = from565(c0), from565(c1)
    return np.stack([a, b, (2 * a + b) / 3, (a + 2 * b) / 3])

def color_block(px, w):
    # px: 16x3 float, w: 16 weights (alpha-based)
    ww = w + 1e-3
    mean = (px * ww[:, None]).sum(0) / ww.sum()
    d = px - mean
    cov = (d * ww[:, None]).T @ d
    axis = np.linalg.eigh(cov)[1][:, -1] if np.abs(cov).sum() > 1e-6 else np.array([1., 1., 1.]) / np.sqrt(3)
    t = d @ axis
    lo, hi = mean + axis * t.min(), mean + axis * t.max()
    best = None
    for _ in range(3):
        cands = [(to565(hi), to565(lo))]
        for c0, c1 in cands:
            if c0 == c1:
                pal = palette(c0, c1); idx = np.zeros(16, int)
            else:
                pal = palette(c0, c1)
                idx = ((px[:, None, :] - pal[None]) ** 2).sum(2).argmin(1)
            err = (((px - pal[idx]) ** 2).sum(1) * ww).sum()
            if best is None or err < best[0]: best = (err, c0, c1, idx)
        # least squares refine of endpoints for current indices
        _, c0, c1, idx = best
        wts = np.array([1, 0, 2 / 3, 1 / 3])[idx]           # weight of endpoint A
        A = np.stack([wts, 1 - wts], 1) * np.sqrt(ww)[:, None]
        B = px * np.sqrt(ww)[:, None]
        sol, *_ = np.linalg.lstsq(A, B, rcond=None)
        hi, lo = sol[0], sol[1]
    _, c0, c1, idx = best
    # BC3 colour block is always 4-colour; keep c0 != c1 ordering irrelevant
    bits = 0
    for i, v in enumerate(idx): bits |= int(v) << (2 * i)
    return struct.pack('<HHI', c0, c1, bits)

def alpha_pal(a0, a1):
    if a0 > a1:
        return np.array([a0, a1] + [((7 - i) * a0 + i * a1) / 7 for i in range(1, 7)], np.float32)
    return np.array([a0, a1] + [((5 - i) * a0 + i * a1) / 5 for i in range(1, 5)] + [0, 255], np.float32)

def alpha_block(al):
    mn, mx = int(al.min()), int(al.max())
    cands = [(mx, mn)] if mx != mn else [(mx, mn)]
    inner = al[(al > 0) & (al < 255)]
    if len(inner): cands.append((int(inner.min()), int(inner.max())))  # 6-level mode with explicit 0/255
    best = None
    for a0, a1 in cands:
        pal = alpha_pal(a0, a1)
        idx = np.abs(al[:, None] - pal[None]).argmin(1)
        err = ((al - pal[idx]) ** 2).sum()
        if best is None or err < best[0]: best = (err, a0, a1, idx)
    _, a0, a1, idx = best
    bits = 0
    for i, v in enumerate(idx): bits |= int(v) << (3 * i)
    return struct.pack('<BB', a0, a1) + bits.to_bytes(6, 'little')

def encode_dxt5(img):
    arr = bleed(np.array(img.convert('RGBA')))
    h, w = arr.shape[:2]
    out = bytearray()
    for by in range(0, h, 4):
        for bx in range(0, w, 4):
            blk = arr[by:by + 4, bx:bx + 4].reshape(16, 4).astype(np.float32)
            out += alpha_block(blk[:, 3])
            out += color_block(blk[:, :3], blk[:, 3] / 255.0)
    return bytes(out)
