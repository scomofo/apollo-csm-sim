"""The Apollo guidance computers' 37 navigation stars, for
data/stars/navigation_stars.json.

    python3 tools/stars/navigation_stars.py

The CMC and the LGC carried a catalog of 37 bright stars, each known to the
crew and the DSKY by an octal code from 01 to 45 (Navi, Regor and Dnoces
are the crew's names for gamma Cassiopeiae, gamma Velorum and iota Ursae
Majoris). This script takes each star's position and proper motion from
the Hipparcos catalogue's new reduction (van Leeuwen 2007, CDS catalogue
I/311, through VizieR), carries the position from the catalogue's epoch,
J1991.25, to Apollo 11's launch day, and writes right ascension and
declination in the ICRS, the frame the simulator's ECI is, with each
star's Hipparcos magnitude. Aberration and parallax are left out: the
largest, the Earth's annual aberration, moves a star by 20 arcseconds, and
the simulator's sky and its computer's catalog are the same positions.

It checks each Hipparcos number against the star's position to a tenth of
a degree, so a wrong number stops it.

Needs network access (vizier.cds.unistra.fr) and nothing beyond the Python
standard library.
"""
import json
import math
import os
import urllib.parse
import urllib.request

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
MISSION = os.path.join(ROOT, "data", "missions", "apollo_11", "mission.json")
OUT = os.path.join(ROOT, "data", "stars", "navigation_stars.json")
VIZIER = "https://vizier.cds.unistra.fr/viz-bin/asu-tsv"

# Octal code, name, Hipparcos number, and the J2000 position to a tenth of
# a degree (right ascension, declination), which checks the number.
STARS = [
    ("01", "Alpheratz", 677, 2.10, 29.09),
    ("02", "Diphda", 3419, 10.90, -17.99),
    ("03", "Navi", 4427, 14.18, 60.72),
    ("04", "Achernar", 7588, 24.43, -57.24),
    ("05", "Polaris", 11767, 37.95, 89.26),
    ("06", "Acamar", 13847, 44.57, -40.30),
    ("07", "Menkar", 14135, 45.57, 4.09),
    ("10", "Mirfak", 15863, 51.08, 49.86),
    ("11", "Aldebaran", 21421, 68.98, 16.51),
    ("12", "Rigel", 24436, 78.63, -8.20),
    ("13", "Capella", 24608, 79.17, 46.00),
    ("14", "Canopus", 30438, 95.99, -52.70),
    ("15", "Sirius", 32349, 101.29, -16.72),
    ("16", "Procyon", 37279, 114.83, 5.22),
    ("17", "Regor", 39953, 122.38, -47.34),
    ("20", "Dnoces", 44127, 134.80, 48.04),
    ("21", "Alphard", 46390, 141.90, -8.66),
    ("22", "Regulus", 49669, 152.09, 11.97),
    ("23", "Denebola", 57632, 177.26, 14.57),
    ("24", "Gienah", 59803, 183.95, -17.54),
    ("25", "Acrux", 60718, 186.65, -63.10),
    ("26", "Spica", 65474, 201.30, -11.16),
    ("27", "Alkaid", 67301, 206.89, 49.31),
    ("30", "Menkent", 68933, 211.67, -36.37),
    ("31", "Arcturus", 69673, 213.92, 19.18),
    ("32", "Alphecca", 76267, 233.67, 26.71),
    ("33", "Antares", 80763, 247.35, -26.43),
    ("34", "Atria", 82273, 252.17, -69.03),
    ("35", "Rasalhague", 86032, 263.73, 12.56),
    ("36", "Vega", 91262, 279.23, 38.78),
    ("37", "Nunki", 92855, 283.82, -26.30),
    ("40", "Altair", 97649, 297.70, 8.87),
    ("41", "Dabih", 100345, 305.25, -14.78),
    ("42", "Peacock", 100751, 306.41, -56.74),
    ("43", "Deneb", 102098, 310.36, 45.28),
    ("44", "Enif", 107315, 326.05, 9.88),
    ("45", "Fomalhaut", 113368, 344.41, -29.62),
]
# Hipparcos's epoch, as a Julian year.
CATALOGUE_EPOCH = 1991.25
J2000_JD = 2451545.0


def fetch():
    """{hip: (ra_deg, dec_deg, pm_ra_mas_yr, pm_dec_mas_yr, hp_mag)}: the
    catalogue's rows for the stars. pmRA includes the cosine of the
    declination."""
    query = urllib.parse.urlencode({
        "-source": "I/311/hip2",
        "-out": "HIP,RArad,DErad,pmRA,pmDE,Hpmag",
        "-out.max": "100",
        "HIP": ",".join(str(s[2]) for s in STARS),
    })
    with urllib.request.urlopen(VIZIER + "?" + query, timeout=60) as r:
        text = r.read().decode()
    rows = {}
    for line in text.splitlines():
        parts = line.split("\t")
        if len(parts) != 6 or not parts[0].strip().isdigit():
            continue
        hip = int(parts[0])
        rows[hip] = tuple(float(p) for p in parts[1:])
    return rows


def separation(ra1, dec1, ra2, dec2):
    """Angle between two directions, deg."""
    a = [math.radians(x) for x in (ra1, dec1, ra2, dec2)]
    c = math.sin(a[1]) * math.sin(a[3]) + math.cos(a[1]) * math.cos(a[3]) * math.cos(a[0] - a[2])
    return math.degrees(math.acos(max(-1.0, min(1.0, c))))


def main():
    with open(MISSION) as f:
        epoch_jd = float(json.load(f)["liftoff_jd"])
    epoch = 2000.0 + (epoch_jd - J2000_JD) / 365.25
    dt = epoch - CATALOGUE_EPOCH
    rows = fetch()
    out = []
    for code, name, hip, ra0, dec0 in STARS:
        if hip not in rows:
            raise SystemExit("HIP %d (%s) not in the catalogue's reply" % (hip, name))
        ra, dec, pm_ra, pm_dec, mag = rows[hip]
        if separation(ra, dec, ra0, dec0) > 0.1:
            raise SystemExit("HIP %d is not %s: it is at %.3f %.3f" % (hip, name, ra, dec))
        # The proper motion, linearly: 22 years move the fastest of them,
        # Arcturus, 50 arcseconds.
        dec_e = dec + pm_dec * dt / 3.6e6
        ra_e = ra + pm_ra * dt / 3.6e6 / math.cos(math.radians(dec))
        out.append({"code": int(code), "name": name, "hip": hip,
                    "ra_deg": round(ra_e % 360.0, 7), "dec_deg": round(dec_e, 7), "mag": round(mag, 2)})
        print("%s %-10s HIP %6d  %11.6f %+11.6f  Hp %5.2f  moved %5.1f arcsec"
              % (code, name, hip, ra_e, dec_e, mag, separation(ra, dec, ra_e, dec_e) * 3600.0))
    data = {
        "_comment": ("The Apollo guidance computers' 37 navigation stars by octal code: the Hipparcos "
                     "catalogue's new reduction (van Leeuwen 2007, CDS I/311), carried by its proper "
                     "motions to Apollo 11's launch day, right ascension and declination in the ICRS "
                     "(deg), and Hipparcos magnitude, from tools/stars/navigation_stars.py [derived]"),
        "epoch_year": round(epoch, 4),
        "stars": out,
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        json.dump(data, f, indent=1)
        f.write("\n")
    print("wrote %s: %d stars at epoch %.4f" % (os.path.relpath(OUT, ROOT), len(out), epoch))


if __name__ == "__main__":
    main()
