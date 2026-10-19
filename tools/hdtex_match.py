"""Match HD replacement textures (PCSX2 dumps of the PS2 game, BC7 DDS --
Bl4ckH4nd's pack in hd-textures/, https://gbatemp.net/threads/my-ps2-packs.621422/) to
SSX 3 Xbox textures dumped by RECOMP_TEX_DUMP, by image content.

  python tools/hdtex_match.py <hd dir> <dump dir> [--out <hd dir>/ssx3_map.txt]
                              [--max-dist 0.05] [--report report.tsv]

Every dump (<key>_<w>x<h>_f<fmt>.tga) is compared with every DDS of the same
aspect ratio: both reduced to 32x32 RGBA, distance = mean absolute
difference of colour (0..1, weighted by alpha) and alpha. The closest DDS
under --max-dist is mapped. It must be a clear winner -- the second best at
least 1.25x further, unless the two DDS files are the same image (the PS2
dumps hold one texture under several palettes) -- and at most half as far
as the dump's own flat average colour, so the match explains its detail.
Near-uniform dumps (all black, all transparent) are skipped: they match
anything.

PS2 alpha runs 0..128 (128 = opaque) and the PCSX2 dumps keep that scale
in many files. A DDS whose alpha never goes above 140 is compared with its
alpha doubled, and its map line gets the flag "a2": the renderer doubles
its alpha. Signatures of the DDS set are cached in <hd dir>/.sig_cache.npz.
Needs Pillow and numpy.
"""
import argparse, os, sys
import numpy as np
from PIL import Image

S = 32

def sig(img):
    im = img.convert("RGBA").resize((S, S), Image.BOX)
    return np.asarray(im, dtype=np.float32) / 255.0

def dist(a, b):
    aa, ba = a[..., 3:4], b[..., 3:4]
    w = np.maximum(aa, ba) + 0.05
    col = (np.abs(a[..., :3] - b[..., :3]) * w).sum() / (w.sum() * 3)
    alp = np.abs(aa - ba).mean()
    return float(col * 0.8 + alp * 0.2)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("hd"); ap.add_argument("dump")
    ap.add_argument("--out"); ap.add_argument("--report")
    ap.add_argument("--max-dist", type=float, default=0.05)
    a = ap.parse_args()
    cache = os.path.join(a.hd, ".sig_cache.npz")
    files = sorted(f for f in os.listdir(a.hd) if f.lower().endswith(".dds"))
    sigs = {}
    if os.path.exists(cache):
        z = np.load(cache, allow_pickle=True)
        sigs = dict(zip(z["names"].tolist(), zip(z["sigs"], z["dims"])))
    todo = [f for f in files if f not in sigs]
    for i, f in enumerate(todo):
        try:
            im = Image.open(os.path.join(a.hd, f))
            sigs[f] = (sig(im), np.array(im.size))
        except Exception as e:
            print("skip", f, e, file=sys.stderr)
        if i % 100 == 99:
            print(f"  decoded {i + 1}/{len(todo)}", file=sys.stderr)
    if todo:
        names = list(sigs)
        np.savez(cache, names=np.array(names, dtype=object),
                 sigs=np.stack([sigs[n][0] for n in names]),
                 dims=np.stack([sigs[n][1] for n in names]))
    by_aspect = {}
    for n, (s, d) in sigs.items():
        a2 = float(s[..., 3].max()) <= 140 / 255
        if a2:
            s = s.copy()
            s[..., 3] = np.minimum(s[..., 3] * 2, 1.0)
        by_aspect.setdefault(round(float(d[0]) / float(d[1]), 3), []).append((n, s, d, a2))

    rows, mapping = [], []
    for f in sorted(os.listdir(a.dump)):
        if not f.endswith(".tga"):
            continue
        key, wh, fmt = f[:-4].split("_")
        w, h = map(int, wh.split("x"))
        if w < 16 or h < 16:
            continue
        ds = sig(Image.open(os.path.join(a.dump, f)))
        if float(ds.std(axis=(0, 1)).max()) < 0.03:
            continue                                  # flat: matches anything
        cands = by_aspect.get(round(w / h, 3), [])
        scored = sorted(((dist(ds, s), i) for i, (n, s, d, a2) in enumerate(cands)))
        if not scored:
            continue
        best = scored[0]
        bn, bs, bd, ba2 = cands[best[1]]
        second = 1.0
        for dd, i in scored[1:]:
            if dist(bs, cands[i][1]) > 0.01:          # another image, not a twin
                second = dd
                break
        # The match must explain the image's detail: at most half as far as
        # the dump's own flat average colour is (else mostly-black images and
        # tile atlases "match" any dark surface).
        flat = dist(ds, np.broadcast_to(ds.mean(axis=(0, 1)), ds.shape))
        ok = best[0] <= a.max_dist and second >= best[0] * 1.25 and best[0] <= flat * 0.5
        rows.append((f, bn, best[0], second, ok))
        if ok:
            mapping.append((key, bn + (" a2" if ba2 else "")))
    out = a.out or os.path.join(a.hd, "ssx3_map.txt")
    with open(out, "w") as fo:
        fo.write("# SSX 3 Xbox texture key -> HD replacement (tools/hdtex_match.py)\n")
        for k, n in mapping:
            fo.write(f"{k} {n}\n")
    if a.report:
        with open(a.report, "w") as fr:
            fr.write("dump\tbest\tdist\tsecond\tmapped\n")
            for r in rows:
                fr.write("%s\t%s\t%.4f\t%.4f\t%d\n" % r)
    print(f"{len(rows)} dumps compared, {len(mapping)} mapped -> {out}")

if __name__ == "__main__":
    main()
