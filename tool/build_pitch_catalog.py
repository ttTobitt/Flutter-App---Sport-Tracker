#!/usr/bin/env python3
"""Fußballplätze Österreichs aus OpenStreetMap als Liste für die App.

Erzeugt assets/osm/pitches_at.json. Die App findet Plätze damit sofort und
ohne Internet (siehe vault/Entscheidungen/Platz-Erkennung und Heatmap.md).

Aktualisieren (z. B. einmal vor der Abgabe):
  1. Österreich-Auszug von Geofabrik laden (ca. 700 MB):
       curl -L -o austria-latest.osm.pbf https://download.geofabrik.de/europe/austria-latest.osm.pbf
  2. pyosmium installieren (einmalig, in einer venv):
       python3 -m venv venv && venv/bin/pip install osmium
  3. Skript laufen lassen (dauert ein paar Minuten):
       venv/bin/python tool/build_pitch_catalog.py austria-latest.osm.pbf
  4. App neu bauen.

Was drin ist:
  - Alle Flächen mit leisure=pitch und sport=soccer (auch "soccer;..."):
    der Umriss und ein Name.
  - Name: der eigene Name des Platzes, sonst der Name der Sportanlage
    (leisure=sports_centre/stadium/recreation_ground), in der er liegt.
    Plätze haben in OSM oft keinen eigenen Namen, die Anlage schon.

Format (klein gehalten, Koordinaten als ganze Zahlen in 1e-6 Grad ≈ 0,1 m):
  {"source": ..., "date": "JJJJ-MM-TT",
   "pitches": [["Name" oder null, [lat, lon, lat, lon, ...]], ...]}

Daten: © OpenStreetMap-Mitwirkende, Lizenz ODbL.
"""
import datetime
import json
import math
import sys
from pathlib import Path

import osmium

GROUNDS = {"sports_centre", "stadium", "recreation_ground"}
CELL = 0.02  # Rastergröße in Grad für die Suche "in welcher Anlage liegt der Platz?"


def is_soccer(tags):
    return tags.get("leisure") == "pitch" and "soccer" in tags.get("sport", "").split(";")


class Handler(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.pitches = []  # (name, [(lat, lon), ...])
        self.grounds = []  # (name, [(lat, lon), ...], bbox)

    def area(self, a):
        tags = a.tags
        soccer = is_soccer(tags)
        ground = tags.get("leisure") in GROUNDS and "name" in tags
        if not (soccer or ground):
            return
        # Nur der äußere Rand. Ein Platz mit Loch kommt praktisch nicht vor.
        rings = list(a.outer_rings())
        if not rings:
            return
        try:
            ring = [(n.lat, n.lon) for n in rings[0]]
        except osmium.InvalidLocationError:
            return
        if len(ring) < 4:
            return
        if soccer:
            self.pitches.append((tags.get("name"), ring))
        else:
            lats = [p[0] for p in ring]
            lons = [p[1] for p in ring]
            bbox = (min(lats), min(lons), max(lats), max(lons))
            self.grounds.append((tags["name"], ring, bbox))


def size_m(ring):
    """Diagonale der Bounding-Box in Metern (grob, zum Aussortieren)"""
    lats = [p[0] for p in ring]
    lons = [p[1] for p in ring]
    dy = (max(lats) - min(lats)) * 111320
    dx = (max(lons) - min(lons)) * 111320 * math.cos(math.radians(lats[0]))
    return math.hypot(dx, dy)


def contains(ring, lat, lon):
    """Punkt im Vieleck (Strahl-Methode)"""
    inside = False
    j = len(ring) - 1
    for i in range(len(ring)):
        (ay, ax), (by, bx) = ring[i], ring[j]
        if (ay > lat) != (by > lat) and lon < (bx - ax) * (lat - ay) / (by - ay) + ax:
            inside = not inside
        j = i
    return inside


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    pbf = sys.argv[1]
    out = Path(__file__).resolve().parent.parent / "assets" / "osm" / "pitches_at.json"

    h = Handler()
    h.apply_file(pbf, locations=True)
    print(f"{len(h.pitches)} Fußballplätze, {len(h.grounds)} benannte Sportanlagen")

    # Anlagen in ein Raster einsortieren, damit nicht jeder Platz mit jeder
    # Anlage verglichen werden muss
    grid = {}
    for g in h.grounds:
        _, _, (la0, lo0, la1, lo1) = g
        for cy in range(math.floor(la0 / CELL), math.floor(la1 / CELL) + 1):
            for cx in range(math.floor(lo0 / CELL), math.floor(lo1 / CELL) + 1):
                grid.setdefault((cy, cx), []).append(g)

    result = []
    skipped = named_by_ground = 0
    for name, ring in h.pitches:
        # Kleinfelder bleiben drin (Kinderfußball), Unsinn wird aussortiert
        if not 15 <= size_m(ring) <= 250:
            skipped += 1
            continue
        lat = sum(p[0] for p in ring) / len(ring)
        lon = sum(p[1] for p in ring) / len(ring)
        if not name:
            for gname, gring, _ in grid.get((math.floor(lat / CELL), math.floor(lon / CELL)), []):
                if contains(gring, lat, lon):
                    name = gname
                    named_by_ground += 1
                    break
        # Der letzte Punkt wiederholt den ersten, den braucht die App nicht
        coords = []
        for plat, plon in ring[:-1]:
            coords += [round(plat * 1e6), round(plon * 1e6)]
        result.append([name, coords])

    data = {
        "source": "© OpenStreetMap-Mitwirkende (ODbL), Auszug Österreich von Geofabrik",
        "date": datetime.date.today().isoformat(),
        "pitches": result,
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    with_name = sum(1 for n, _ in result if n)
    print(f"{len(result)} gespeichert ({skipped} aussortiert), "
          f"{with_name} mit Namen (davon {named_by_ground} von der Anlage)")
    print(f"{out} ({out.stat().st_size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
