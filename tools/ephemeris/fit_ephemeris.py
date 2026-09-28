"""Fit the Moon's and the Sun's ephemeris for a mission (data/ephemeris/)
from JPL's.

    python3 tools/ephemeris/fit_ephemeris.py [mission]

The mission is a directory of data/missions/, apollo_11 unless named. The
simulator flies in an Earth-centred inertial frame, the ICRF (the J2000
equator and equinox), with time as ground elapsed time (GET): seconds after
the mission's range zero, its liftoff_jd (Apollo 11's 1969-07-16 13:32:00
UTC). This script writes, for GET -2 to +30 days in 4-day segments:

    moon              the Moon's geocentric position (m), from JPL Horizons
                      (DE441). Its velocity is the series' derivative.
    sun               the Sun's geocentric position (m), from JPL Horizons.
    moon_orientation  the right ascension and declination of the Moon's
                      north pole and its prime meridian's angle W (degrees),
                      the IAU Working Group on Cartographic Coordinates and
                      Rotational Elements' model (Archinal et al. 2011), as
                      NAIF's text PCK pck00010.tpc gives it. Its frame is the
                      Moon's mean Earth/polar axis frame, which the landing
                      site's coordinates and the terrain maps use.

Each is a Chebyshev series per segment, fitted by interpolation at the
Chebyshev nodes. The script then checks every series against vectors and
angles held out of the fit, prints the worst errors, and writes a sample of
them to tests/fixtures/ephemeris_check.json (Apollo 11's;
ephemeris_check_<mission>.json for another) for tests/unit/test_ephemeris.gd.

Needs network access (ssd.jpl.nasa.gov, naif.jpl.nasa.gov) and nothing
beyond the Python standard library.
"""
import json
import math
import os
import re
import sys
import urllib.parse
import urllib.request

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
MISSION_ID = sys.argv[1] if len(sys.argv) > 1 else "apollo_11"
MISSION = os.path.join(ROOT, "data", "missions", MISSION_ID, "mission.json")
OUT = os.path.join(ROOT, "data", "ephemeris", MISSION_ID + ".json")
CHECK_OUT = os.path.join(ROOT, "tests", "fixtures", "ephemeris_check%s.json"
                         % ("" if MISSION_ID == "apollo_11" else "_" + MISSION_ID))

HORIZONS = "https://ssd.jpl.nasa.gov/api/horizons.api"
PCK = "https://naif.jpl.nasa.gov/pub/naif/generic_kernels/pck/pck00010.tpc"

DAY = 86400.0
SEGMENT_S = 4.0 * DAY
START_GET_S = -2.0 * DAY
SEGMENTS = 8
# Degree 9 holds the Moon to the 0.1 m the Julian dates' precision allows
# (degree 8 leaves 0.6 m, 7 leaves 7 m); the propagator evaluates it at
# every step.
DEGREE = {"moon": 9, "sun": 8, "moon_orientation": 8}
# Held out of the fit: these fractions of each segment, ends included.
CHECK_AT = [0.0, 0.003, 0.07, 0.19, 0.31, 0.44, 0.56, 0.69, 0.81, 0.93, 0.997]
# Of those, the fixture keeps these for the GDScript tests.
FIXTURE_AT = [0.003, 0.44, 0.93]
J2000_JD = 2451545.0


def tt_minus_utc(jd_utc):
    """TT - UTC, s, for 1968-02-01 to 1972-01-01: 32.184 s plus TAI - UTC,
    which then ran at 4.2131700 s + (MJD - 39126) x 0.002592 s (USNO,
    tai-utc.dat). TDB differs from TT by under 2 ms."""
    mjd = jd_utc - 2400000.5
    assert 39887 <= mjd < 41317, "TAI - UTC rule only holds for 1968 to 1971"
    return 32.184 + 4.2131700 + (mjd - 39126.0) * 0.002592


def nodes(n):
    """The n Chebyshev-Gauss nodes on [-1, 1], highest first."""
    return [math.cos(math.pi * (j + 0.5) / n) for j in range(n)]


def interpolate(values):
    """Chebyshev coefficients c[0..n-1] of the series through [param values]
    at nodes(n): f(x) = sum c[k] T_k(x)."""
    n = len(values)
    c = []
    for k in range(n):
        s = sum(values[j] * math.cos(math.pi * k * (j + 0.5) / n) for j in range(n))
        c.append(s * (1.0 if k == 0 else 2.0) / n)
    return c


def evaluate(c, x):
    """The series c at x in [-1, 1], and its derivative d/dx."""
    t0, t1 = 1.0, x
    u0, u1 = 1.0, 2.0 * x  # U_{k-1}: dT_k/dx = k U_{k-1}
    f = c[0] + (c[1] * x if len(c) > 1 else 0.0)
    d = c[1] if len(c) > 1 else 0.0
    for k in range(2, len(c)):
        t0, t1 = t1, 2.0 * x * t1 - t0
        f += c[k] * t1
        d += c[k] * k * u1
        u0, u1 = u1, 2.0 * x * u1 - u0
    return f, d


def segment_times(seg, fractions):
    a = START_GET_S + seg * SEGMENT_S
    return [a + f * SEGMENT_S for f in fractions]


def node_times(seg, n):
    a = START_GET_S + seg * SEGMENT_S
    return [a + (x + 1.0) * SEGMENT_S / 2.0 for x in nodes(n)]


def horizons(target, epoch_jd, gets):
    """Geocentric ICRF states of [param target] (a Horizons COMMAND) at GETs
    [param gets], s: {get: [x, y, z, vx, vy, vz]} in m and m/s. Horizons
    reads the times as UTC and returns them as it read them (JDUT); the GET
    keys are those, back from JD."""
    out = {}
    # Horizons returns a time list in time order.
    gets = sorted(set(gets))
    for i in range(0, len(gets), 60):
        chunk = gets[i:i + 60]
        tlist = " ".join("%.9f" % (epoch_jd + g / DAY) for g in chunk)
        q = {"format": "text", "COMMAND": "'%s'" % target, "OBJ_DATA": "'NO'", "MAKE_EPHEM": "'YES'",
             "EPHEM_TYPE": "'VECTORS'", "CENTER": "'500@399'", "REF_PLANE": "'FRAME'",
             "REF_SYSTEM": "'ICRF'", "VEC_TABLE": "'2'", "OUT_UNITS": "'KM-S'", "CSV_FORMAT": "'YES'",
             "VEC_LABELS": "'NO'", "TIME_TYPE": "'UT'", "TLIST": "'%s'" % tlist}
        with urllib.request.urlopen(HORIZONS + "?" + urllib.parse.urlencode(q), timeout=120) as r:
            text = r.read().decode()
        assert "DE441" in text and "Reference frame : ICRF" in text, text[:2000]
        body = text.split("$$SOE")[1].split("$$EOE")[0]
        rows = [ln.split(",") for ln in body.strip().splitlines()]
        assert len(rows) == len(chunk), "asked for %d times, got %d" % (len(chunk), len(rows))
        for g, row in zip(chunk, rows):
            jd = float(row[0])
            got = (jd - epoch_jd) * DAY
            assert abs(got - g) < 1e-3, "Horizons moved %.3f s to %.3f s" % (g, got)
            out[g] = [float(v) * 1000.0 for v in row[2:8]]
    return out


def sub_earth(epoch_jd, gets):
    """Horizons' sub-Earth point on the Moon (east longitude, latitude,
    degrees) in the Moon's mean Earth/polar axis frame at GETs
    [param gets]: {get: [lon, lat]}. An independent check of the frame the
    orientation series and the positions make together."""
    gets = sorted(set(gets))
    tlist = " ".join("%.9f" % (epoch_jd + g / DAY) for g in gets)
    q = {"format": "text", "COMMAND": "'301'", "OBJ_DATA": "'NO'", "MAKE_EPHEM": "'YES'",
         "EPHEM_TYPE": "'OBSERVER'", "CENTER": "'500@399'", "QUANTITIES": "'14'", "CSV_FORMAT": "'YES'",
         "ANG_FORMAT": "'DEG'", "TIME_TYPE": "'UT'", "TLIST": "'%s'" % tlist}
    with urllib.request.urlopen(HORIZONS + "?" + urllib.parse.urlencode(q), timeout=120) as r:
        text = r.read().decode()
    assert "MOON_ME" in text and "East-longitude positive" in text, text[:2000]
    rows = [ln.split(",") for ln in text.split("$$SOE")[1].split("$$EOE")[0].strip().splitlines()]
    assert len(rows) == len(gets)
    return {g: [float(row[3]), float(row[4])] for g, row in zip(gets, rows)}


def moon_fixed_rows(angles):
    """The Moon-fixed axes in the ICRF from [param angles] (pole right
    ascension, declination, prime meridian W, degrees): the rows of
    Rz(W) Rx(90 - dec) Rz(90 + ra), X, Y then Z."""
    a, d, w = [math.radians(v) for v in angles]
    ca, sa = math.cos(a), math.sin(a)
    cd, sd = math.cos(d), math.sin(d)
    cw, sw = math.cos(w), math.sin(w)
    return [[-cw * sa - sw * sd * ca, cw * ca - sw * sd * sa, sw * cd],
            [sw * sa - cw * sd * ca, -sw * ca - cw * sd * sa, cw * cd],
            [cd * ca, cd * sa, sd]]


def pck_values(text):
    """The assignments in a NAIF text kernel's data blocks: {name: [floats]}."""
    data = []
    on = False
    for ln in text.splitlines():
        s = ln.strip()
        if s.startswith("\\begindata"):
            on = True
        elif s.startswith("\\begintext"):
            on = False
        elif on:
            data.append(ln)
    out = {}
    for m in re.finditer(r"(\w+)\s*=\s*\(([^)]*)\)", "\n".join(data)):
        out[m.group(1)] = [float(v.replace("D", "E")) for v in m.group(2).split()]
    return out


def moon_angles(pck, jd_tdb):
    """Right ascension and declination of the Moon's pole and the angle W of
    its prime meridian, degrees, from the PCK's IAU model at [param jd_tdb].
    The nutation-precession angles run per Julian century; W per day."""
    d = jd_tdb - J2000_JD
    t = d / 36525.0
    ang = pck["BODY3_NUT_PREC_ANGLES"]
    theta = [math.radians(ang[2 * i] + ang[2 * i + 1] * t) for i in range(len(ang) // 2)]
    ra = pck["BODY301_POLE_RA"]
    dec = pck["BODY301_POLE_DEC"]
    pm = pck["BODY301_PM"]
    a = ra[0] + ra[1] * t + ra[2] * t * t
    b = dec[0] + dec[1] * t + dec[2] * t * t
    w = pm[0] + pm[1] * d + pm[2] * d * d
    for i, s in enumerate(pck["BODY301_NUT_PREC_RA"]):
        a += s * math.sin(theta[i])
    for i, s in enumerate(pck["BODY301_NUT_PREC_DEC"]):
        b += s * math.cos(theta[i])
    for i, s in enumerate(pck["BODY301_NUT_PREC_PM"]):
        w += s * math.sin(theta[i])
    return [a, b, w]


def main():
    with open(MISSION) as f:
        mission = json.load(f)
    epoch = float(mission["liftoff_jd"])
    name = str(mission.get("name", "Apollo 11"))
    with urllib.request.urlopen(PCK, timeout=120) as r:
        pck = pck_values(r.read().decode())

    # W runs from J2000, some -146,600 degrees by 1969: whole turns off, so
    # it starts the mission between 0 and 360.
    w_turns = 360.0 * math.floor(moon_angles(pck, epoch + tt_minus_utc(epoch) / DAY)[2] / 360.0)

    def orientation(gets):
        out = {}
        for g in gets:
            jd_utc = epoch + g / DAY
            a = moon_angles(pck, jd_utc + tt_minus_utc(jd_utc) / DAY)
            out[g] = [a[0], a[1], a[2] - w_turns]
        return out

    fit_times = {name: [g for s in range(SEGMENTS) for g in node_times(s, n + 1)] for name, n in DEGREE.items()}
    check_times = [g for s in range(SEGMENTS) for g in segment_times(s, CHECK_AT)]
    source = {
        "moon": lambda gets: horizons("301", epoch, gets),
        "sun": lambda gets: horizons("10", epoch, gets),
        "moon_orientation": orientation,
    }
    fitted = {}
    checks = {}
    for name in DEGREE:
        values = source[name](fit_times[name] + check_times)
        n = DEGREE[name] + 1
        segs = []
        for s in range(SEGMENTS):
            at = node_times(s, n)
            segs.append([interpolate([values[g][i] for g in at]) for i in range(3)])
        fitted[name] = segs
        checks[name] = {g: values[g] for g in check_times}

    def series(name, g):
        s = min(max(int((g - START_GET_S) // SEGMENT_S), 0), SEGMENTS - 1)
        x = 2.0 * (g - START_GET_S - s * SEGMENT_S) / SEGMENT_S - 1.0
        fd = [evaluate(c, x) for c in fitted[name][s]]
        return [v[0] for v in fd], [v[1] * 2.0 / SEGMENT_S for v in fd]

    # The worst errors against the held-out values.
    worst = {"moon_pos_m": 0.0, "moon_vel_mps": 0.0, "sun_deg": 0.0, "sun_dist_m": 0.0, "orientation_deg": 0.0}
    for g in check_times:
        p, v = series("moon", g)
        ref = checks["moon"][g]
        worst["moon_pos_m"] = max(worst["moon_pos_m"], math.dist(p, ref[0:3]))
        worst["moon_vel_mps"] = max(worst["moon_vel_mps"], math.dist(v, ref[3:6]))
        p, _v = series("sun", g)
        ref = checks["sun"][g][0:3]
        cross = math.hypot(p[1] * ref[2] - p[2] * ref[1], p[2] * ref[0] - p[0] * ref[2], p[0] * ref[1] - p[1] * ref[0])
        worst["sun_deg"] = max(worst["sun_deg"], math.degrees(math.atan2(cross, sum(a * b for a, b in zip(p, ref)))))
        worst["sun_dist_m"] = max(worst["sun_dist_m"], abs(math.hypot(*p) - math.hypot(*ref)))
        a, _r = series("moon_orientation", g)
        worst["orientation_deg"] = max(worst["orientation_deg"],
                                       max(abs(x - y) for x, y in zip(a, checks["moon_orientation"][g])))
    # The frame the series make, against Horizons' own sub-Earth point: the
    # IAU model and DE441's lunar frame differ by some 0.005 degrees.
    sample = [g for s in range(SEGMENTS) for g in segment_times(s, FIXTURE_AT)]
    horizons_sub = sub_earth(epoch, sample)
    worst["sub_earth_deg"] = 0.0
    for g in sample:
        rows = moon_fixed_rows(series("moon_orientation", g)[0])
        p, _v = series("moon", g)
        e = [-sum(r[i] * p[i] for i in range(3)) for r in rows]
        lon = math.degrees(math.atan2(e[1], e[0]))
        lat = math.degrees(math.asin(e[2] / math.hypot(*e)))
        ref = horizons_sub[g]
        worst["sub_earth_deg"] = max(worst["sub_earth_deg"], abs((lon - ref[0] + 180.0) % 360.0 - 180.0),
                                     abs(lat - ref[1]))
    for k, v in worst.items():
        print("worst %-16s %.3g" % (k, v))
    assert worst["moon_pos_m"] < 1.0 and worst["sun_deg"] < 1e-5 and worst["orientation_deg"] < 1e-6, worst
    assert worst["sub_earth_deg"] < 0.02, worst

    out = {
        "_comment": ("The Moon's and the Sun's geocentric positions and the Moon's orientation for " + name + ", "
                     "fitted by tools/ephemeris/fit_ephemeris.py. Frame: ICRF (J2000 equator and equinox), "
                     "Earth-centred. Time: GET, s after the mission's liftoff_jd (UTC). Each quantity is a "
                     "Chebyshev series in each segment of segment_s from start_get_s: for x in [-1, 1] "
                     "across the segment, value = sum c[k] T_k(x), one list of c per component."),
        "_source": ("Positions: JPL Horizons, DE441, geocentric geometric states in the ICRF "
                    "(ssd.jpl.nasa.gov). Moon orientation: the IAU WGCCRE 2009 model (Archinal et al. "
                    "2011, Celest. Mech. Dyn. Astr. 109) from NAIF's pck00010.tpc, in the Moon's mean "
                    "Earth/polar axis frame; TDB from UTC by TAI - UTC (USNO) + 32.184 s."),
        "_fit_error": {k: float("%.3g" % v) for k, v in worst.items()},
        "epoch_jd_utc": epoch,
        "start_get_s": START_GET_S,
        "segment_s": SEGMENT_S,
        "segments": SEGMENTS,
        "moon": {"units": "m", "segments": fitted["moon"]},
        "sun": {"units": "m", "segments": fitted["sun"]},
        "moon_orientation": {"units": "deg", "angles": ["pole_ra", "pole_dec", "prime_meridian"],
                             "segments": fitted["moon_orientation"]},
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        json.dump(out, f, indent=1)
        f.write("\n")
    fixture = {
        "_comment": ("Held out of tools/ephemeris/fit_ephemeris.py's fit: JPL Horizons (DE441) geocentric "
                     "ICRF states of the Moon (m, m/s) and the Sun (m), the IAU model's Moon "
                     "orientation angles (deg), and Horizons' sub-Earth point on the Moon (east "
                     "longitude and latitude in the mean Earth/polar axis frame, deg), at these GETs."),
        "epoch_jd_utc": epoch,
        "points": [{"get_s": g, "moon": checks["moon"][g], "sun": checks["sun"][g][0:3],
                    "moon_orientation": checks["moon_orientation"][g], "sub_earth": horizons_sub[g]}
                   for g in sample],
    }
    with open(CHECK_OUT, "w") as f:
        json.dump(fixture, f, indent=1)
        f.write("\n")
    print("wrote %s and %s" % (os.path.relpath(OUT, ROOT), os.path.relpath(CHECK_OUT, ROOT)))


if __name__ == "__main__":
    main()
