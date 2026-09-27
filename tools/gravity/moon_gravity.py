"""The Moon's gravity field from GRAIL, truncated for the simulator
(data/gravity/moon.json), and a reference orbit integrated through it for
the tests (tests/fixtures/moon_gravity_check.json).

    python3 tools/gravity/moon_gravity.py [--study | --hold]

The field is JPL's GL1800F (Park et al. 2025), from GRAIL's primary and
extended missions, as the PDS Geosciences Node distributes it in the
Moon's mean Earth/polar axis frame (GL1800F_ME: rotated there from the
principal axes by DE440's angles). That is the frame the simulator's
Moon-fixed axes, its landing site and its terrain maps use. Its
coefficients are fully normalised, about a reference radius of 1738 km,
and its GM is 4902.800306 km^3/s^2.

The file runs to degree 1800 (198 MB) in fixed 122-byte records sorted by
degree, so the script fetches only the records it needs with an HTTP
range request.

--study prints how much of the field's acceleration each truncation leaves
out, against degree 150, at 60 nmi, where Columbia orbits, and at 15 km,
the pericynthion Eagle's descent orbit dips to; and how far a 60 nmi orbit
flown through each truncation drifts in a day from one flown through
degree 100. Short wavelengths average out along an orbit, so the drift is
what matters: degree 30's orbit keeps its apsides within 0.16 km of degree
100's (the mission report gives Apollo 11's to 0.1 nmi) and comes 1.3 km
along the track from it, where degree 20's apsides go 0.5 km off and
degree 40's 0.05 km, at twice degree 30's cost. The simulator keeps
degree DEGREE.

--hold prints what the simulator's economy costs: it samples the field
once every 30 s, on a fixed grid of time, at each interval's middle where
the orbit will be then, and interpolates between the samples with a
cubic. Against sampling at every RK4 stage, that moves a 60 nmi orbit 10 m
in a day and its apsides under a metre.

The reference orbit is the check that the simulator's field, a separate
recursion in GDScript, flies an orbit as this script's does: a 60 nmi
orbit about a Moon alone, turning at its sidereal rate, integrated by RK4
for twelve hours from the same start, its radius and position recorded at
each hour. This script evaluates the field by summing the normalised
Legendre functions directly in spherical coordinates, a different
algorithm from the simulator's Cunningham recursion.

Needs network access (pds-geosciences.wustl.edu) and nothing beyond the
Python standard library.
"""
import json
import math
import os
import sys
import urllib.request

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "data", "gravity", "moon.json")
CHECK_OUT = os.path.join(ROOT, "tests", "fixtures", "moon_gravity_check.json")

URL = ("https://pds-geosciences.wustl.edu/grail/grail-l-lgrs-5-rdr-v1/"
       "grail_1001/shadr/jggrx_1800f_me_sha.tab")
RECORD = 122
HEADER_RECORDS = 2

DEGREE = 30
STUDY_DEGREE = 150
STUDY_KEEP = [8, 12, 16, 20, 24, 30, 40, 50, 60, 80]

# The reference orbit: 60 nmi up, near the equator, retrograde as
# Apollo's were, about a Moon turning once a sidereal month.
CHECK_RADIUS = 1737400.0 + 60.0 * 1852.0
CHECK_INCLINATION_DEG = 178.8
CHECK_HOURS = 12
CHECK_STEP_S = 20.0
SIDEREAL_MONTH_S = 27.321661 * 86400.0


def fetch(max_degree):
    """The header and the coefficient records to [max_degree]."""
    records = HEADER_RECORDS + max_degree * (max_degree + 3) // 2
    req = urllib.request.Request(URL, headers={"Range": "bytes=0-%d" % (records * RECORD - 1)})
    with urllib.request.urlopen(req, timeout=120) as r:
        raw = r.read().decode("ascii")
    if len(raw) != records * RECORD:
        raise SystemExit("expected %d bytes, got %d" % (records * RECORD, len(raw)))
    head = [f.strip() for f in raw[:HEADER_RECORDS * RECORD].split(",")]
    radius = float(head[0]) * 1000.0
    gm = float(head[1]) * 1e9
    if int(head[5]) != 1:
        raise SystemExit("the coefficients are not normalised")
    c = {}
    s = {}
    for k in range(HEADER_RECORDS, records):
        f = [x.strip() for x in raw[k * RECORD:(k + 1) * RECORD].split(",")]
        n, m = int(f[0]), int(f[1])
        c[(n, m)] = float(f[2])
        s[(n, m)] = float(f[3])
    for n in range(1, max_degree + 1):
        for m in range(n + 1):
            if (n, m) not in c:
                raise SystemExit("missing coefficient %d,%d" % (n, m))
    return gm, radius, c, s


def legendre(nmax, u):
    """Fully normalised associated Legendre functions P[n][m](u) and their
    derivatives with respect to latitude, u the sine of the latitude."""
    cl = math.sqrt(max(0.0, 1.0 - u * u))
    p = [[0.0] * (n + 2) for n in range(nmax + 2)]
    p[0][0] = 1.0
    for m in range(1, nmax + 2):
        k = math.sqrt(3.0) if m == 1 else math.sqrt((2 * m + 1) / (2 * m))
        p[m][m] = k * cl * p[m - 1][m - 1]
    for m in range(0, nmax + 1):
        p[m + 1][m] = math.sqrt(2 * m + 3) * u * p[m][m]
        for n in range(m + 2, nmax + 2):
            a = math.sqrt((2 * n - 1) * (2 * n + 1) / ((n - m) * (n + m)))
            b = math.sqrt((2 * n + 1) * (n + m - 1) * (n - m - 1) / ((n - m) * (n + m) * (2 * n - 3)))
            p[n][m] = a * u * p[n - 1][m] - b * p[n - 2][m]
    tan = u / cl
    dp = [[0.0] * (n + 1) for n in range(nmax + 1)]
    for n in range(nmax + 1):
        for m in range(n + 1):
            k = math.sqrt((n - m) * (n + m + 1) / (2.0 if m == 0 else 1.0))
            dp[n][m] = k * p[n][m + 1] - m * tan * p[n][m]
    return p, dp


def accel_by_degree(field, x, y, z, nmax):
    """The field's acceleration at Moon-fixed (x, y, z), m/s^2, degree by
    degree from 2 to [nmax]: the potential's gradient in spherical
    coordinates. Returns a list whose entry n is degree n's (ax, ay, az)."""
    gm, radius, c, s = field
    r = math.sqrt(x * x + y * y + z * z)
    u = z / r
    cl = math.sqrt(max(0.0, 1.0 - u * u))
    lon = math.atan2(y, x)
    p, dp = legendre(nmax, u)
    cosm = [math.cos(m * lon) for m in range(nmax + 1)]
    sinm = [math.sin(m * lon) for m in range(nmax + 1)]
    q = radius / r
    k = gm / (r * r)
    sl_, cl_ = math.sin(lon), math.cos(lon)
    out = [(0.0, 0.0, 0.0), (0.0, 0.0, 0.0)]
    qn = q * q
    for n in range(2, nmax + 1):
        sr = sl = sp = 0.0
        for m in range(n + 1):
            cs = c[(n, m)] * cosm[m] + s[(n, m)] * sinm[m]
            sr += p[n][m] * cs
            sp += dp[n][m] * cs
            sl += m * p[n][m] * (s[(n, m)] * cosm[m] - c[(n, m)] * sinm[m])
        gr = -(n + 1) * qn * sr * k
        gp = qn * sp * k
        gl = qn * sl * k / cl
        out.append((gr * cl * cl_ - gp * u * cl_ - gl * sl_,
                    gr * cl * sl_ - gp * u * sl_ + gl * cl_,
                    gr * u + gp * cl))
        qn *= q
    return out


def accel(field, x, y, z, nmax):
    """The field's acceleration from degrees 2 to [nmax] at Moon-fixed
    (x, y, z), m/s^2."""
    parts = accel_by_degree(field, x, y, z, nmax)
    return tuple(sum(a[i] for a in parts) for i in range(3))


def norm(v):
    return math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])


def study(field):
    """How much of degree STUDY_DEGREE's pull each truncation leaves out."""
    points = []
    for i in range(12):
        lat = math.asin(-0.95 + 1.9 * (i + 0.5) / 12.0)
        for j in range(24):
            lon = 2.0 * math.pi * (j + 0.5) / 24.0
            points.append((math.cos(lat) * math.cos(lon), math.cos(lat) * math.sin(lon), math.sin(lat)))
    for label, alt in (("60 nmi", 60.0 * 1852.0), ("15 km", 15000.0)):
        r = field[1] + alt
        beyond2 = []
        left = {k: [] for k in STUDY_KEEP}
        for (ux, uy, uz) in points:
            parts = accel_by_degree(field, ux * r, uy * r, uz * r, STUDY_DEGREE)
            beyond2.append(norm([sum(a[i] for a in parts[3:]) for i in range(3)]))
            for k in STUDY_KEEP:
                left[k].append(norm([sum(a[i] for a in parts[k + 1:]) for i in range(3)]))
        rms = lambda xs: 1e6 * math.sqrt(sum(a * a for a in xs) / len(xs))
        print("%s up, over %d points (um/s^2):" % (label, len(points)))
        print("  degrees 3 to %d, the pull beyond J2 and C22: rms %.1f, max %.1f" % (
            STUDY_DEGREE, rms(beyond2), 1e6 * max(beyond2)))
        for k in STUDY_KEEP:
            print("  kept to %3d, left out: rms %8.3f, max %8.3f" % (k, rms(left[k]), 1e6 * max(left[k])))


def rk4(field, state, h, t, omega, degree=DEGREE):
    """One RK4 step of an orbit about the Moon alone, inertial, the Moon
    turning at [omega] about its pole from the inertial axes at t = 0,
    its field to [degree]."""
    gm = field[0]

    def acc(tt, x, y, z):
        th = omega * tt
        c, s = math.cos(th), math.sin(th)
        fx, fy, fz = c * x + s * y, -s * x + c * y, z
        a = accel(field, fx, fy, fz, degree)
        ax, ay, az = c * a[0] - s * a[1], s * a[0] + c * a[1], a[2]
        r3 = (x * x + y * y + z * z) ** 1.5
        return (ax - gm * x / r3, ay - gm * y / r3, az - gm * z / r3)

    x, y, z, vx, vy, vz = state
    k1 = acc(t, x, y, z)
    h2 = h / 2.0
    p2 = (x + vx * h2, y + vy * h2, z + vz * h2)
    v2 = (vx + k1[0] * h2, vy + k1[1] * h2, vz + k1[2] * h2)
    k2 = acc(t + h2, *p2)
    p3 = (x + v2[0] * h2, y + v2[1] * h2, z + v2[2] * h2)
    v3 = (vx + k2[0] * h2, vy + k2[1] * h2, vz + k2[2] * h2)
    k3 = acc(t + h2, *p3)
    p4 = (x + v3[0] * h, y + v3[1] * h, z + v3[2] * h)
    v4 = (vx + k3[0] * h, vy + k3[1] * h, vz + k3[2] * h)
    k4 = acc(t + h, *p4)
    return (x + h / 6.0 * (vx + 2 * v2[0] + 2 * v3[0] + v4[0]),
            y + h / 6.0 * (vy + 2 * v2[1] + 2 * v3[1] + v4[1]),
            z + h / 6.0 * (vz + 2 * v2[2] + 2 * v3[2] + v4[2]),
            vx + h / 6.0 * (k1[0] + 2 * k2[0] + 2 * k3[0] + k4[0]),
            vy + h / 6.0 * (k1[1] + 2 * k2[1] + 2 * k3[1] + k4[1]),
            vz + h / 6.0 * (k1[2] + 2 * k2[2] + 2 * k3[2] + k4[2]))


def reference_orbit(field):
    gm = field[0]
    inc = math.radians(CHECK_INCLINATION_DEG)
    v = math.sqrt(gm / CHECK_RADIUS)
    state = (CHECK_RADIUS, 0.0, 0.0, 0.0, v * math.cos(inc), v * math.sin(inc))
    omega = 2.0 * math.pi / SIDEREAL_MONTH_S
    steps_per_hour = int(round(3600.0 / CHECK_STEP_S))
    t = 0.0
    hours = []
    for hour in range(1, CHECK_HOURS + 1):
        for _ in range(steps_per_hour):
            state = rk4(field, state, CHECK_STEP_S, t, omega)
            t += CHECK_STEP_S
        hours.append({"t_s": t, "state": list(state)})
        r = math.sqrt(sum(x * x for x in state[:3]))
        print("  %2d h: radius %.1f m" % (hour, r))
    return {"radius_m": CHECK_RADIUS, "inclination_deg": CHECK_INCLINATION_DEG, "step_s": CHECK_STEP_S,
            "omega_rad_s": omega, "gm_m3s2": gm, "degree": DEGREE, "start": [state_i for state_i in (
                CHECK_RADIUS, 0.0, 0.0, 0.0, v * math.cos(inc), v * math.sin(inc))], "hours": hours}


def start_state(gm):
    inc = math.radians(CHECK_INCLINATION_DEG)
    v = math.sqrt(gm / CHECK_RADIUS)
    return (CHECK_RADIUS, 0.0, 0.0, 0.0, v * math.cos(inc), v * math.sin(inc))


def apsides(gm, st):
    """Osculating periapsis and apoapsis altitudes above 1737.4 km, m."""
    r = norm(st[:3])
    v2 = st[3] ** 2 + st[4] ** 2 + st[5] ** 2
    a = 1.0 / (2.0 / r - v2 / gm)
    hx = st[1] * st[5] - st[2] * st[4]
    hy = st[2] * st[3] - st[0] * st[5]
    hz = st[0] * st[4] - st[1] * st[3]
    e = math.sqrt(max(0.0, 1.0 - (hx * hx + hy * hy + hz * hz) / (gm * a)))
    return a * (1.0 - e) - 1737400.0, a * (1.0 + e) - 1737400.0


def orbit_study(field, keep, reference, hours):
    """How far orbits flown through truncated fields drift from one flown
    through degree [reference], over [hours]."""
    gm = field[0]
    omega = 2.0 * math.pi / SIDEREAL_MONTH_S
    steps = int(round(3600.0 / CHECK_STEP_S))
    runs = {}
    for k in keep + [reference]:
        st = start_state(gm)
        t = 0.0
        track = []
        for _ in range(hours):
            for _ in range(steps):
                st = rk4(field, st, CHECK_STEP_S, t, omega, k)
                t += CHECK_STEP_S
            track.append(st)
        runs[k] = track
    ref = runs[reference]
    pe, ap = apsides(gm, ref[-1])
    print("orbits 60 nmi up for %d h against degree %d's (periapsis %.2f km, apoapsis %.2f km at the end):" % (
        hours, reference, pe / 1000.0, ap / 1000.0))
    for k in keep:
        d = [norm([runs[k][h][i] - ref[h][i] for i in range(3)]) for h in range(hours)]
        kpe, kap = apsides(gm, runs[k][-1])
        print("  degree %3d: off by %8.1f m at 6 h, %8.1f m at 12 h, %8.1f m at %d h; apsides off %+.3f, %+.3f km" % (
            k, d[5], d[11], d[-1], hours, (kpe - pe) / 1000.0, (kap - ap) / 1000.0))


def fly_sampled(field, degree, hours, step, hold):
    """An orbit flown as the simulator flies it: the field sampled at the
    middles of a fixed grid of [hold]-second intervals, where the orbit
    will be then (carried on from the step's start by a third-order series
    in the central pull), and interpolated in time between the samples, a
    Catmull-Rom cubic, at each RK4 stage."""
    gm = field[0]
    omega = 2.0 * math.pi / SIDEREAL_MONTH_S
    st = start_state(gm)
    t = 0.0
    samples = {}
    track = []
    per_hour = int(round(3600.0 / step))

    def sample(k, st, t):
        if k not in samples:
            h = (k + 0.5) * hold - t
            r = norm(st[:3])
            rv = sum(st[i] * st[i + 3] for i in range(3)) / (r * r)
            ka = -0.5 * gm / r ** 3 * h * h
            kj = -gm / r ** 3 * h ** 3 / 6.0
            px, py, pz = (st[i] + st[i + 3] * h + st[i] * ka + kj * (st[i + 3] - 3.0 * rv * st[i]) for i in range(3))
            th = omega * (t + h)
            c, s_ = math.cos(th), math.sin(th)
            a = accel(field, c * px + s_ * py, -s_ * px + c * py, pz, degree)
            samples[k] = (c * a[0] - s_ * a[1], s_ * a[0] + c * a[1], a[2])
        return samples[k]

    def fld(tau, st, t):
        u = tau / hold - 0.5
        k = math.floor(u)
        w = u - k
        p = [sample(k + j, st, t) for j in (-1, 0, 1, 2)]
        c = (-0.5 * w ** 3 + w * w - 0.5 * w, 1.5 * w ** 3 - 2.5 * w * w + 1.0,
             -1.5 * w ** 3 + 2.0 * w * w + 0.5 * w, 0.5 * w ** 3 - 0.5 * w * w)
        return tuple(sum(c[j] * p[j][i] for j in range(4)) for i in range(3))

    for _ in range(hours):
        for _ in range(per_hour):
            f1, f2, f4 = fld(t, st, t), fld(t + step / 2.0, st, t), fld(t + step, st, t)

            def acc(f, x, y, z):
                r3 = (x * x + y * y + z * z) ** 1.5
                return (f[0] - gm * x / r3, f[1] - gm * y / r3, f[2] - gm * z / r3)

            x, y, z, vx, vy, vz = st
            h2 = step / 2.0
            k1 = acc(f1, x, y, z)
            k2 = acc(f2, x + vx * h2, y + vy * h2, z + vz * h2)
            v2 = (vx + k1[0] * h2, vy + k1[1] * h2, vz + k1[2] * h2)
            k3 = acc(f2, x + v2[0] * h2, y + v2[1] * h2, z + v2[2] * h2)
            v3 = (vx + k2[0] * h2, vy + k2[1] * h2, vz + k2[2] * h2)
            k4 = acc(f4, x + v3[0] * step, y + v3[1] * step, z + v3[2] * step)
            v4 = (vx + k3[0] * step, vy + k3[1] * step, vz + k3[2] * step)
            st = (x + step / 6.0 * (vx + 2 * v2[0] + 2 * v3[0] + v4[0]),
                  y + step / 6.0 * (vy + 2 * v2[1] + 2 * v3[1] + v4[1]),
                  z + step / 6.0 * (vz + 2 * v2[2] + 2 * v3[2] + v4[2]),
                  vx + step / 6.0 * (k1[0] + 2 * k2[0] + 2 * k3[0] + k4[0]),
                  vy + step / 6.0 * (k1[1] + 2 * k2[1] + 2 * k3[1] + k4[1]),
                  vz + step / 6.0 * (k1[2] + 2 * k2[2] + 2 * k3[2] + k4[2]))
            t += step
            for k in [k for k in samples if (k + 2.5) * hold < t]:
                del samples[k]
        track.append(st)
    return track


def hold_study(field, degree, hours, step, holds):
    """How far holding the field between samples moves the orbit."""
    gm = field[0]
    omega = 2.0 * math.pi / SIDEREAL_MONTH_S
    st = start_state(gm)
    t = 0.0
    ref = []
    for _ in range(hours):
        for _ in range(int(round(3600.0 / step))):
            st = rk4(field, st, step, t, omega, degree)
            t += step
        ref.append(st)
    pe, ap = apsides(gm, ref[-1])
    print("degree %d for %d h at %.0f s steps, sampled at every stage (apsides %.2f x %.2f km), against sampled on a grid:" % (
        degree, hours, step, pe / 1000.0, ap / 1000.0))
    for hold in holds:
        tr = fly_sampled(field, degree, hours, step, hold)
        d = norm([tr[-1][i] - ref[-1][i] for i in range(3)])
        kpe, kap = apsides(gm, tr[-1])
        print("  every %4.0f s: off by %7.1f m at %d h; apsides off %+.3f, %+.3f km" % (
            hold, d, hours, (kpe - pe) / 1000.0, (kap - ap) / 1000.0))


def main():
    if "--hold" in sys.argv:
        hold_study(fetch(DEGREE), DEGREE, 24, 5.0, [10.0, 20.0, 30.0, 60.0])
        return
    if "--study" in sys.argv:
        print("fetching degrees to %d" % STUDY_DEGREE)
        field = fetch(STUDY_DEGREE)
        study(field)
        orbit_study(field, [2, 8, 12, 16, 20, 24, 30, 40, 50, 60], 100, 24)
        return
    field = fetch(DEGREE)
    gm, radius, c, s = field
    out = {
        "model": "GL1800F_ME",
        "source": "JPL GRAIL gravity field GL1800F in the Moon's mean Earth/polar axis frame "
                  "(Park et al. 2025), PDS Geosciences Node, jggrx_1800f_me_sha.tab",
        "frame": "Moon mean Earth/polar axis (DE440)",
        "gm_m3s2": gm,
        "radius_m": radius,
        "degree": DEGREE,
        "normalized": True,
        "c": [c[(n, m)] for n in range(2, DEGREE + 1) for m in range(n + 1)],
        "s": [s[(n, m)] for n in range(2, DEGREE + 1) for m in range(n + 1)],
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        json.dump(out, f, separators=(",", ":"))
        f.write("\n")
    print("wrote %s: degree %d, %d coefficients" % (OUT, DEGREE, len(out["c"])))
    print("reference orbit, %d h at %.0f s steps:" % (CHECK_HOURS, CHECK_STEP_S))
    check = reference_orbit(field)
    with open(CHECK_OUT, "w") as f:
        json.dump(check, f, indent=1)
        f.write("\n")
    print("wrote %s" % CHECK_OUT)


if __name__ == "__main__":
    main()
