"""Downloads every filling station in Ireland (Republic and Northern Ireland)
from OpenStreetMap and writes assets/stations.json as [[name, lat, lon], ...].
Runs in CI before the build. If the download fails, the existing file is kept.

Station data © OpenStreetMap contributors, ODbL.
"""
import json
import pathlib
import sys
import urllib.parse
import urllib.request

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "stations.json"
QUERY = """
[out:json][timeout:120];
(
  area["ISO3166-1"="IE"][admin_level=2];
  area["ISO3166-2"="GB-NIR"];
)->.ire;
nwr["amenity"="fuel"](area.ire);
out center tags;
"""
SERVERS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]


def main():
    data = None
    for url in SERVERS:
        try:
            req = urllib.request.Request(
                url,
                data=urllib.parse.urlencode({"data": QUERY}).encode(),
                headers={"User-Agent": "PumpWatch-build/1.0 (viptechviptech@gmail.com)"},
            )
            with urllib.request.urlopen(req, timeout=180) as r:
                data = json.load(r)
            break
        except Exception as e:  # try the next server
            print(f"{url}: {e}", file=sys.stderr)
    if not data:
        print("Station download failed; keeping the existing assets/stations.json")
        return
    rows = []
    for el in data.get("elements", []):
        lat = el.get("lat") or (el.get("center") or {}).get("lat")
        lon = el.get("lon") or (el.get("center") or {}).get("lon")
        if lat is None or lon is None:
            continue
        t = el.get("tags", {})
        brand = (t.get("brand") or t.get("operator") or "").strip()
        name = (t.get("name") or "").strip()
        place = (t.get("addr:city") or t.get("addr:suburb") or t.get("addr:street") or "").strip()
        label = name or brand or "Filling station"
        if brand and brand.lower() not in label.lower():
            label = f"{brand} {label}"
        if place and place.lower() not in label.lower():
            label = f"{label}, {place}"
        rows.append([label[:80], round(lat, 6), round(lon, 6)])
    rows.sort(key=lambda r: (r[1], r[2]))
    OUT.write_text(json.dumps(rows, ensure_ascii=False, separators=(",", ":")))
    print(f"Saved {len(rows)} stations to {OUT}")


if __name__ == "__main__":
    main()
