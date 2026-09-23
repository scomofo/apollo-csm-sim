"""Build the terrain around Tranquility Base (data/terrain/) from NASA's
lunar elevation maps.

    python3 tools/terrain/build_terrain.py [--cache DIR]

Four layers of heights relative to the 1737.4 km reference sphere, finest
first where they overlap (src/dynamics/terrain.gd blends them):

    site      LROC NAC DTM of the Apollo 11 site (NAC_DTM_APOLLO11, 2 m/px),
              resampled to 4 m around the LM: 2.7 km east-west, 1.6 km
              north-south. West crater and Little West are in it.
    near      SLDEM2015 (LOLA and SELENE Terrain Camera, 512 px/deg, 59 m)
              over the final approach, 8 km past the site to 34 km before it.
    approach  SLDEM2015 averaged to 256 px/deg (118 m) from 22.8 E to 31 E:
              everything the landing radar can see.
    moon      LOLA LDEM_4 averaged to 1 px/deg: the rest of the Moon.

Only the rows each layer needs are downloaded, with HTTP range requests
(about 50 MB). The raw rows are kept in the cache directory, so a second
run doesn't download them again. Needs numpy.
"""
import argparse
import json
import math
import os
import urllib.request

import numpy as np

R_MOON_M = 1737400.0
M_PER_DEG = R_MOON_M * math.pi / 180.0
# Where the LM stands, as mapped from LROC NAC images.
LM_LAT = 0.67416
LM_LON = 23.47314

PDS_LOLA = "https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data"
LDEM_4 = PDS_LOLA + "/lola_gdr/cylindrical/img/ldem_4.img"
SLDEM = PDS_LOLA + "/sldem2015/tiles/float_img/sldem2015_512_00n_30n_000_045_float.img"
NAC_DTM = ("https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/SDP/"
           "NAC_DTM/APOLLO11/NAC_DTM_APOLLO11.TIF")

# SLDEM2015 tile 00N-30N, 0-45E: 15360 lines x 23040 float32 samples (km
# above 1737.4 km); line L's centre is at 30 - (L + 0.5) / 512 degrees.
SLDEM_SAMPLES = 23040
SLDEM_ROWS = (14822, 15208)
# NAC_DTM_APOLLO11: 13978 lines x 2111 float32 samples (m above 1737.4 km)
# from byte 112496 (PDS counts from 1), equirectangular about 1 N, 2 m/px.
NAC_OFFSET = 112495
NAC_SAMPLES = 2111
NAC_ROWS = (7846, 9212)
NAC_RES = 15161.67521207          # px/deg in latitude
NAC_LAT_TOP = 1.2365388           # top edge of line 0
NAC_LON_WEST = 23.3722758         # west edge of sample 0
NAC_NODATA = -1e30


def fetch(url, path, first=None, last=None):
    if os.path.exists(path):
        return
    req = urllib.request.Request(url)
    if first is not None:
        req.add_header("Range", "bytes=%d-%d" % (first, last))
    print("downloading", url, "" if first is None else "bytes %d-%d" % (first, last))
    with urllib.request.urlopen(req, timeout=600) as r, open(path + ".part", "wb") as f:
        while True:
            b = r.read(1 << 20)
            if not b:
                break
            f.write(b)
    os.replace(path + ".part", path)


def bilinear(z, y, x):
    """Sample grid z at fractional row y and column x (arrays)."""
    y0 = np.clip(np.floor(y).astype(int), 0, z.shape[0] - 2)
    x0 = np.clip(np.floor(x).astype(int), 0, z.shape[1] - 2)
    fy = y - y0
    fx = x - x0
    return (z[y0, x0] * (1 - fx) * (1 - fy) + z[y0, x0 + 1] * fx * (1 - fy)
            + z[y0 + 1, x0] * (1 - fx) * fy + z[y0 + 1, x0 + 1] * fx * fy)


def block_mean(z, k):
    h, w = (z.shape[0] // k) * k, (z.shape[1] // k) * k
    return z[:h, :w].reshape(h // k, k, w // k, k).mean(axis=(1, 3))


def layer(name, z, lat_top, lon_left, ppd, blend_px, offset_m, scale_m, out_dir, wrap=False):
    """Write one layer: z[row, col] in metres above the reference sphere, row 0's
    centre at lat_top, col 0's at lon_left, ppd rows (and columns) per degree."""
    dn = np.round((z - offset_m) / scale_m)
    assert dn.min() >= -32768 and dn.max() <= 32767, name
    fn = "%s.bin" % name
    dn.astype("<i2").tofile(os.path.join(out_dir, fn))
    print("%-9s %4d x %4d  %6.1f m/px  %.1f..%.1f m" % (name, z.shape[0], z.shape[1], M_PER_DEG / ppd, z.min(), z.max()))
    return {"name": name, "file": fn, "rows": int(z.shape[0]), "cols": int(z.shape[1]),
            "lat_top": lat_top, "lon_left": lon_left, "ppd": ppd, "blend_px": blend_px,
            "offset_m": offset_m, "scale_m": scale_m, "wrap": wrap}


def main():
    ap = argparse.ArgumentParser()
    here = os.path.dirname(os.path.abspath(__file__))
    ap.add_argument("--cache", default=os.path.join(here, ".cache"))
    ap.add_argument("--out", default=os.path.join(here, "..", "..", "data", "terrain"))
    a = ap.parse_args()
    os.makedirs(a.cache, exist_ok=True)
    os.makedirs(a.out, exist_ok=True)
    c = lambda f: os.path.join(a.cache, f)

    fetch(LDEM_4, c("ldem_4.img"))
    rb = SLDEM_SAMPLES * 4
    fetch(SLDEM, c("sldem_rows.bin"), SLDEM_ROWS[0] * rb, SLDEM_ROWS[1] * rb - 1)
    nb = NAC_SAMPLES * 4
    fetch(NAC_DTM, c("nac_rows.bin"), NAC_OFFSET + NAC_ROWS[0] * nb, NAC_OFFSET + NAC_ROWS[1] * nb - 1)

    ldem = np.fromfile(c("ldem_4.img"), dtype="<i2").reshape(720, 1440).astype(np.float64) * 0.5
    sld = np.fromfile(c("sldem_rows.bin"), dtype="<f4").reshape(-1, SLDEM_SAMPLES).astype(np.float64) * 1000.0
    nac = np.fromfile(c("nac_rows.bin"), dtype="<f4").reshape(-1, NAC_SAMPLES).astype(np.float64)

    def sld_rc(lat, lon):
        return (30.0 - lat) * 512.0 - 0.5 - SLDEM_ROWS[0], lon * 512.0 - 0.5

    layers = []
    # The Moon at 1 px/deg: row 0 at 89.5 N, column 0 at 0.5 E.
    layers.append(layer("moon", block_mean(ldem, 4), 89.5, 0.5, 1.0, 0, 0.0, 1.0, a.out, wrap=True))

    # The approach: SLDEM2015 averaged 2 x 2 (256 px/deg), about the ground track.
    r0, c0 = sld_rc(LM_LAT + 0.125, 22.8)
    r0, c0 = int(round(r0)), int(round(c0))
    rows, cols = 128, int(round(8.2 * 512))
    z = block_mean(sld[r0:r0 + rows, c0:c0 + cols], 2)
    layers.append(layer("approach", z, 30.0 - (r0 + SLDEM_ROWS[0] + 1.0) / 512.0,
                        (c0 + 1.0) / 512.0, 256.0, 8, -2000.0, 0.1, a.out))

    # The final approach at SLDEM2015's own 512 px/deg.
    r0, c0 = sld_rc(LM_LAT + 0.06, 23.2)
    r0, c0 = int(round(r0)), int(round(c0))
    rows, cols = 62, int(round(1.4 * 512))
    z = sld[r0:r0 + rows, c0:c0 + cols]
    layers.append(layer("near", z, 30.0 - (r0 + SLDEM_ROWS[0] + 0.5) / 512.0,
                        (c0 + 0.5) / 512.0, 512.0, 8, -2000.0, 0.1, a.out))

    # The site: the NAC DTM resampled to 4 m (square pixels at this
    # latitude), its gaps filled from SLDEM2015.
    ppd = M_PER_DEG / 4.0
    lat_top = LM_LAT + 0.0265
    lon_left = LM_LON - 1530.0 / M_PER_DEG
    rows = int(round(0.053 * ppd))
    cols = int(round((2650.0) / 4.0))
    lat = lat_top - np.arange(rows)[:, None] / ppd + np.zeros((1, cols))
    lon = lon_left + np.arange(cols)[None, :] / ppd + np.zeros((rows, 1))
    nac_lon_res = NAC_RES * math.cos(math.radians(1.0))
    ny = (NAC_LAT_TOP - lat) * NAC_RES - 0.5 - NAC_ROWS[0]
    nx = (lon - NAC_LON_WEST) * nac_lon_res - 0.5
    # Each 4 m post averages the 2 m posts around it.
    ok = nac > NAC_NODATA
    nf = np.where(ok, nac, 0.0)
    good = np.zeros_like(ny)
    zn = np.zeros_like(ny)
    for dy in (-0.5, 0.5):
        for dx in (-0.5, 0.5):
            good += bilinear(ok.astype(np.float64), ny + dy, nx + dx) / 4.0
            zn += bilinear(nf, ny + dy, nx + dx) / 4.0
    sy, sx = sld_rc(lat, lon)
    zs = bilinear(sld, sy, sx)
    z = np.where(good > 0.999, zn / np.maximum(good, 1e-9), zs)
    site_h = float(bilinear(nf, np.array([(NAC_LAT_TOP - LM_LAT) * NAC_RES - 0.5 - NAC_ROWS[0]]),
                            np.array([(LM_LON - NAC_LON_WEST) * nac_lon_res - 0.5]))[0])
    print("gaps filled from SLDEM2015: %d of %d posts; the LM's spot: %.2f m" % (np.sum(good <= 0.999), z.size, site_h))
    layers.append(layer("site", z, lat_top, lon_left, ppd, 25, -1930.0, 0.01, a.out))

    manifest = {
        "_comment": "Heights relative to the 1737.4 km reference sphere: DN * scale_m + offset_m, "
                    "int16 little-endian, row-major, row 0 northmost. Row r's centre is at "
                    "lat_top - r / ppd, column c's at lon_left + c / ppd (degrees east). "
                    "Built by tools/terrain/build_terrain.py; sources in NOTICE.",
        "_source": "LROC NAC_DTM_APOLLO11 (NASA/GSFC/Arizona State University); SLDEM2015 "
                   "(Barker et al., 2016, LOLA and SELENE TC); LOLA LDEM_4 (NASA/GSFC)",
        "lm_lat_deg": LM_LAT, "lm_lon_deg": LM_LON,
        "layers": layers[::-1],
    }
    with open(os.path.join(a.out, "terrain.json"), "w") as f:
        json.dump(manifest, f, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main()
