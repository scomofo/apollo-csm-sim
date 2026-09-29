"""A mission's parking orbit in the frame the ephemeris uses (the ICRF),
for its mission.json's parking_orbit block.

    python3 tools/ephemeris/parking_orbit.py [mission]

The mission is apollo_11 unless named (MISSIONS below holds each one's
figures). The Saturn V flight evaluation report gives the orbit at
insertion: its inclination, its descending node (in the equator, eastward
from the launch meridian at range zero), the insertion's time after range
zero and its point (geodetic latitude and longitude, altitude). Apollo
11's (AS-506, MPR-SAT-FE-69-9, Table 4-5): 32.521 deg, 123.088 deg,
709.3 s, 32.672 N 52.694 W at 191.1 km. This script places the launch
meridian by Greenwich mean sidereal time at range zero (IAU 1982; UT1 is
taken as UTC), takes the plane from the mean equator of date to J2000 by
the IAU 1976 precession, and prints the orbit's inclination, right
ascension of the ascending node and the insertion's argument of latitude
in the ICRF. Nutation, polar motion and the ICRF's offset from J2000 are
left out: each is under 0.01 deg here. It checks the insertion point lies
in the plane.

It prints the plane TLI left the stack in, for mission.json's tli block
(plane_normal): the same report gives it at TLI, 10 s after the S-IVB's
second cutoff signal, on the postflight trajectory, in the same frame as
the parking orbit's (Apollo 11's, Table 10-6: 31.383 deg and 121.847
deg). The IU's guidance flies TLI into it (Rtcc.plan_tli()).

It also prints the launch pad REFSMMAT for mission.json's
launch_refsmmat block: the orientation the CMC's IMU was released at
liftoff, X horizontal along the flight azimuth (the report's), Z down
along the pad's geodetic vertical and Y = Z x X, each row a stable member
axis in the ICRF.

For a mission whose figures give two burns' velocities to be gained both
in the IMU's axes and in the Earth-centred inertial axes of its mission
report ("burns", Apollo 13's MCC-2 and PC+2, flown on the same platform),
it prints the REFSMMAT that platform held: the rotation that takes the
one pair onto the other (TRIAD, the longer burn's direction kept exactly),
from the report's axes, taken as the mean equator and equinox of the
Besselian year of the flight [estimated], to the ICRF.
"""
import json
import math
import os
import sys

from fit_ephemeris import tt_minus_utc

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
MISSION_ID = sys.argv[1] if len(sys.argv) > 1 else "apollo_11"
MISSION = os.path.join(ROOT, "data", "missions", MISSION_ID, "mission.json")

# Launch Complex 39A's pad, geodetic (NASA KSC); 39B's for the missions
# that name it.
PAD_39A = (28.608389, -80.604333)
PAD_39B = (28.627306, -80.620869)
# Each mission's Saturn V flight evaluation report: the flight azimuth (deg
# east of north), the orbit at insertion (actual) and at TLI (the postflight
# trajectory), nodes east of the launch meridian at range zero.
MISSIONS = {
    # AS-506, MPR-SAT-FE-69-9: section 4 (the azimuth), Tables 4-5 and 10-6.
    "apollo_11": {"flight_azimuth": 72.058, "inclination": 32.521, "descending_node": 123.088,
                  "insertion_s": 709.3, "insertion_lat": 32.672, "insertion_lon": -52.694,
                  "insertion_alt_km": 191.1, "tli_inclination": 31.383, "tli_descending_node": 121.847},
    # AS-503, MPR-SAT-FE-69-1: section 4.1 (the azimuth), Tables 4-6 and 4-7.
    # Those tables count the nodes east of Greenwich at range zero, the
    # launch meridian's 80.604 deg west less (the IU targeted the parking
    # orbit's at 123.004 deg from the launch meridian, their 42.397 deg).
    "apollo_8": {"flight_azimuth": 72.124, "inclination": 32.509, "descending_node": 42.415 - PAD_39A[1],
                 "insertion_s": 694.98, "insertion_lat": 32.649, "insertion_lon": -53.292,
                 "insertion_alt_km": 191.36, "tli_inclination": 30.636, "tli_descending_node": 38.983 - PAD_39A[1]},
    # AS-505, from Launch Complex 39B: the Apollo/Saturn V Postflight
    # Trajectory, AS-505 (Boeing D5-15560-5): section 3 (the azimuth), Tables
    # 4-II (insertion, the S-IVB's first cutoff plus 10 s) and 3-V (TLI).
    "apollo_10": {"pad": PAD_39B, "flight_azimuth": 72.028, "inclination": 32.546, "descending_node": 123.132,
                  "insertion_s": 713.76, "insertion_lat": 32.700, "insertion_lon": -52.526,
                  "insertion_alt_km": 191.37, "tli_inclination": 31.698, "tli_descending_node": 123.515},
    # AS-507, from Launch Complex 39A: the Saturn V flight evaluation report
    # (MPR-SAT-FE-70-1): section 4.1 (the azimuth), Tables 4-5 (insertion)
    # and 4-6 (TLI).
    "apollo_12": {"flight_azimuth": 72.029, "inclination": 32.540, "descending_node": 123.126,
                  "insertion_s": 703.91, "insertion_lat": 32.682, "insertion_lon": -53.131,
                  "insertion_alt_km": 190.9, "tli_inclination": 30.355, "tli_descending_node": 120.338},
    # AS-508, from Launch Complex 39A: the Apollo/Saturn V postflight
    # trajectory (the azimuth, 72.043 deg) and the Saturn V flight
    # evaluation report (MPR-SAT-FE-70-2): Tables 4-5 (insertion) and 4-6
    # (TLI). Its burns: MCC-2's and PC+2's velocities to be gained in the
    # LM IMU's axes as planned (the Apollo 13 Mission Operations Report,
    # Appendix D) and in the mission report's Earth-centred inertial axes as
    # desired (MSC-02680, Table 6.4-I), ft/s, the table's signs reversed:
    # its components run against the burns (the simulator's PC+2, its N81
    # the flown PAD's to a few ft/s, burns along their negative), and taken
    # so the platform's Z axis lies within 0.06 deg of the ecliptic's south
    # pole and its Y axis against the equinox, a passive thermal control
    # REFSMMAT's form.
    "apollo_13": {"flight_azimuth": 72.043, "inclination": 32.525, "descending_node": 123.084,
                  "insertion_s": 759.83, "insertion_lat": 32.694, "insertion_lon": -50.490,
                  "insertion_alt_km": 191.6, "tli_inclination": 31.817, "tli_descending_node": 122.997,
                  "burns": {"imu": [[-37.89, 2.96, -1.21], [743.08, -426.42, 90.84]],
                            "eci": [[-2.9, 34.3, 16.2], [426.4, -645.6, -379.0]]}},
}
FIGURES = MISSIONS[MISSION_ID]
PAD_LAT, PAD_LON = FIGURES.get("pad", PAD_39A)
FLIGHT_AZIMUTH = FIGURES["flight_azimuth"]
INCLINATION = FIGURES["inclination"]
DESCENDING_NODE = FIGURES["descending_node"]
INSERTION_S = FIGURES["insertion_s"]
INSERTION_LAT = FIGURES["insertion_lat"]
INSERTION_LON = FIGURES["insertion_lon"]
INSERTION_ALT_KM = FIGURES["insertion_alt_km"]
TLI_INCLINATION = FIGURES["tli_inclination"]
TLI_DESCENDING_NODE = FIGURES["tli_descending_node"]
# WGS 84.
A_KM = 6378.137
F = 1.0 / 298.257223563
J2000_JD = 2451545.0


def gmst_deg(jd_ut1):
    """Greenwich mean sidereal time, degrees (IAU 1982)."""
    t = (jd_ut1 - J2000_JD) / 36525.0
    return (280.46061837 + 360.98564736629 * (jd_ut1 - J2000_JD) + 0.000387933 * t * t
            - t * t * t / 38710000.0) % 360.0


def rz(a):
    c, s = math.cos(a), math.sin(a)
    return [[c, s, 0.0], [-s, c, 0.0], [0.0, 0.0, 1.0]]


def ry(a):
    c, s = math.cos(a), math.sin(a)
    return [[c, 0.0, -s], [0.0, 1.0, 0.0], [s, 0.0, c]]


def mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def apply(m, v):
    return [sum(m[i][k] * v[k] for k in range(3)) for i in range(3)]


def transpose(m):
    return [[m[j][i] for j in range(3)] for i in range(3)]


def precession(jd_tt):
    """J2000 mean equator and equinox to those of [param jd_tt] (IAU 1976)."""
    t = (jd_tt - J2000_JD) / 36525.0
    arcsec = math.pi / 180.0 / 3600.0
    zeta = (2306.2181 * t + 0.30188 * t * t + 0.017998 * t ** 3) * arcsec
    z = (2306.2181 * t + 1.09468 * t * t + 0.018203 * t ** 3) * arcsec
    theta = (2004.3109 * t - 0.42665 * t * t - 0.041833 * t ** 3) * arcsec
    return mul(rz(-z), mul(ry(theta), rz(-zeta)))


def plane_normal(epoch, to_j2000, inclination, descending_node):
    """The unit normal (r x v) of the orbit plane of [param inclination]
    and [param descending_node] (deg; the node counted in the equator
    eastward from the launch meridian at range zero), in the ICRF. In the
    mean equator of date the ascending node lies 180 degrees from the
    descending one."""
    node = math.radians(gmst_deg(epoch) + PAD_LON + descending_node - 180.0)
    inc = math.radians(inclination)
    return apply(to_j2000, [math.sin(inc) * math.sin(node), -math.sin(inc) * math.cos(node), math.cos(inc)])


def main():
    with open(MISSION) as f:
        epoch = float(json.load(f)["liftoff_jd"])
    tt = epoch + tt_minus_utc(epoch) / 86400.0
    to_j2000 = transpose(precession(tt))
    normal = plane_normal(epoch, to_j2000, INCLINATION, DESCENDING_NODE)
    raan = math.degrees(math.atan2(normal[0], -normal[1])) % 360.0
    i_icrf = math.degrees(math.acos(normal[2]))
    # The insertion point, from the Earth-fixed frame to the ICRF.
    lat, lon = math.radians(INSERTION_LAT), math.radians(INSERTION_LON)
    e2 = F * (2.0 - F)
    n = A_KM / math.sqrt(1.0 - e2 * math.sin(lat) ** 2)
    ecef = [(n + INSERTION_ALT_KM) * math.cos(lat) * math.cos(lon),
            (n + INSERTION_ALT_KM) * math.cos(lat) * math.sin(lon),
            (n * (1.0 - e2) + INSERTION_ALT_KM) * math.sin(lat)]
    theta = math.radians(gmst_deg(epoch + INSERTION_S / 86400.0))
    r = apply(to_j2000, apply(transpose(rz(theta)), ecef))
    rn = math.sqrt(sum(x * x for x in r))
    out_of_plane = math.degrees(math.asin(sum(a * b for a, b in zip(r, normal)) / rn))
    p = [math.cos(math.radians(raan)), math.sin(math.radians(raan)), 0.0]
    q = [normal[1] * p[2] - normal[2] * p[1], normal[2] * p[0] - normal[0] * p[2], normal[0] * p[1] - normal[1] * p[0]]
    u = math.degrees(math.atan2(sum(a * b for a, b in zip(r, q)), sum(a * b for a, b in zip(r, p))))
    print("ICRF: inclination %.3f deg, RAAN %.3f deg; insertion at argument of latitude %.2f deg, "
          "radius %.1f km (%.1f km over the equatorial radius), %.3f deg out of the plane"
          % (i_icrf, raan, u, rn, rn - A_KM, out_of_plane))
    tli = plane_normal(epoch, to_j2000, TLI_INCLINATION, TLI_DESCENDING_NODE)
    turn = math.degrees(math.acos(max(-1.0, min(1.0, sum(a * b for a, b in zip(normal, tli))))))
    print('TLI plane: "plane_normal": [%.9f, %.9f, %.9f], %.3f deg from the parking orbit\'s at insertion'
          % (tli[0], tli[1], tli[2], turn))
    # The launch pad REFSMMAT: the pad's local frame at range zero.
    lat, lon, az = math.radians(PAD_LAT), math.radians(PAD_LON), math.radians(FLIGHT_AZIMUTH)
    up = [math.cos(lat) * math.cos(lon), math.cos(lat) * math.sin(lon), math.sin(lat)]
    north = [-math.sin(lat) * math.cos(lon), -math.sin(lat) * math.sin(lon), math.cos(lat)]
    east = [-math.sin(lon), math.cos(lon), 0.0]
    x = [math.cos(az) * north[i] + math.sin(az) * east[i] for i in range(3)]
    z = [-c for c in up]
    y = [z[1] * x[2] - z[2] * x[1], z[2] * x[0] - z[0] * x[2], z[0] * x[1] - z[1] * x[0]]
    to_icrf = mul(to_j2000, transpose(rz(math.radians(gmst_deg(epoch)))))
    rows = [apply(to_icrf, a) for a in (x, y, z)]
    # Its Y axis against the parking orbit's normal: the orbital-rate pitch
    # in the parking orbit turns the CSM about it, so the middle gimbal
    # stays near zero.
    tilt = math.degrees(math.acos(max(-1.0, min(1.0, -sum(a * b for a, b in zip(rows[1], normal))))))
    print("launch pad REFSMMAT (ICRF rows):")
    for name, row in zip("xyz", rows):
        print('  "%s": [%.9f, %.9f, %.9f]' % (name, row[0], row[1], row[2]))
    print("its Y axis is %.3f deg from the parking orbit's negative normal" % tilt)
    if "burns" in FIGURES:
        burn_refsmmat(epoch)


def unit(v):
    n = math.sqrt(sum(x * x for x in v))
    return [x / n for x in v]


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def triad(p, q):
    """Rows: p's direction, then the normal to p and q, then the third."""
    t1 = unit(p)
    t2 = unit(cross(p, q))
    return [t1, t2, cross(t1, t2)]


def burn_refsmmat(epoch):
    """The REFSMMAT the burns' platform held (the docstring's), its rows
    the stable member's axes in the ICRF."""
    b = FIGURES["burns"]
    imu_1, imu_2 = b["imu"]
    eci_1, eci_2 = b["eci"]
    angle = lambda u, v: math.degrees(math.acos(sum(x * y for x, y in zip(unit(u), unit(v)))))
    print("the burns %.3f deg apart in the IMU's axes, %.3f in the report's" % (angle(imu_1, imu_2), angle(eci_1, eci_2)))
    # Stable member from report axes: IMU triad's transpose times the
    # report's triad.
    m = mul(transpose(triad(imu_2, imu_1)), triad(eci_2, eci_1))
    # The Besselian year of the flight: its start, B1970.0.
    year = round(2000.0 + (epoch - J2000_JD) / 365.25)
    jd_b = 2415020.31352 + 365.242198781 * (year - 1900)
    to_j2000 = transpose(precession(jd_b))
    print("burns' REFSMMAT (ICRF rows, from the mean equator and equinox of B%d.0):" % year)
    for name, row in zip("xyz", m):
        r = apply(to_j2000, row)
        print('  "%s": [%.9f, %.9f, %.9f]' % (name, r[0], r[1], r[2]))


if __name__ == "__main__":
    main()
