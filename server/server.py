#!/usr/bin/env python3
"""PumpWatch test server.

Runs on your PC so the PumpWatch app on your phone can share petrol and
diesel prices. Needs only Python 3.8+ (no extra packages).

    python server.py            start on port 8080
    python server.py --demo     also add a few demo stations around Dublin
    python server.py --port 9000

Your phone and PC must be on the same Wi-Fi. The app's Settings screen
needs the address this server prints when it starts.

Hivemapper (Bee Maps) key: put it in a file called beemaps_key.txt next
to this script (the base64 "username:key" string from the Bee Maps
console), or set the BEEMAPS_KEY environment variable. Never commit it.
"""

import argparse
import json
import math
import os
import socket
import sqlite3
import sys
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(HERE, "pumpwatch.db")
BEEMAPS_URL = "https://beemaps.com/api/developer/map-data"
FUELS = ("petrol", "diesel")
MATCH_RADIUS_M = 150  # a report this close to a known station counts as that station

_db_lock = threading.Lock()


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def distance_m(lat1, lon1, lat2, lon2):
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def db():
    con = sqlite3.connect(DB_PATH, check_same_thread=False)
    con.row_factory = sqlite3.Row
    return con


def init_db(demo):
    with _db_lock, db() as con:
        con.executescript(
            """
            CREATE TABLE IF NOT EXISTS stations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                lat REAL NOT NULL,
                lon REAL NOT NULL,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS reports (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                station_id INTEGER NOT NULL REFERENCES stations(id),
                fuel TEXT NOT NULL,
                price REAL NOT NULL,
                source TEXT NOT NULL,
                reported_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS reports_station ON reports(station_id, fuel, reported_at);
            """
        )
        if demo and con.execute("SELECT COUNT(*) FROM stations").fetchone()[0] == 0:
            demo_rows = [
                ("Demo Station 1", 53.3498, -6.2603, 1.719, 1.689),
                ("Demo Station 2", 53.3381, -6.2592, 1.749, 1.709),
                ("Demo Station 3", 53.3610, -6.2700, 1.769, 1.729),
                ("Demo Station 4", 53.3300, -6.2850, 1.789, 1.739),
            ]
            for name, lat, lon, petrol, diesel in demo_rows:
                cur = con.execute(
                    "INSERT INTO stations(name, lat, lon, created_at) VALUES (?,?,?,?)",
                    (name, lat, lon, now_iso()),
                )
                for fuel, price in (("petrol", petrol), ("diesel", diesel)):
                    con.execute(
                        "INSERT INTO reports(station_id, fuel, price, source, reported_at) VALUES (?,?,?,?,?)",
                        (cur.lastrowid, fuel, price, "demo", now_iso()),
                    )
            print("Added 4 demo stations around Dublin city centre.")


def station_payload(con, row, lat=None, lon=None):
    prices = {}
    for fuel in FUELS:
        r = con.execute(
            "SELECT price, source, reported_at FROM reports WHERE station_id=? AND fuel=? "
            "ORDER BY reported_at DESC, id DESC LIMIT 1",
            (row["id"], fuel),
        ).fetchone()
        if r:
            prices[fuel] = {"price": r["price"], "source": r["source"], "reported_at": r["reported_at"]}
    out = {
        "id": row["id"],
        "name": row["name"],
        "lat": row["lat"],
        "lon": row["lon"],
        "prices": prices,
    }
    if lat is not None:
        out["distance_km"] = round(distance_m(lat, lon, row["lat"], row["lon"]) / 1000.0, 2)
    return out


def load_beemaps_key():
    key = os.environ.get("BEEMAPS_KEY", "").strip()
    if key:
        return key
    path = os.path.join(HERE, "beemaps_key.txt")
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return f.read().strip()
    return ""


def hivemapper_check(lat, lon, radius_m):
    key = load_beemaps_key()
    if not key:
        return 400, {"error": "No Bee Maps key. Put it in server/beemaps_key.txt and restart."}
    body = json.dumps(
        {"type": ["mapFeatures"], "geometry": {"type": "Point", "coordinates": [lon, lat], "radius": radius_m}}
    ).encode()
    req = urllib.request.Request(
        BEEMAPS_URL,
        data=body,
        headers={
            "Authorization": "Basic " + key,
            "Content-Type": "application/json",
            "User-Agent": "curl/8.5.0",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=40) as resp:
            data = json.load(resp)
    except urllib.error.HTTPError as e:
        return 502, {"error": "Bee Maps returned HTTP %s" % e.code}
    except Exception as e:  # network problems
        return 502, {"error": "Could not reach Bee Maps: %s" % e}
    feats = (data.get("mapFeatureResults") or {}).get("data") or []
    classes = {}
    for f in feats:
        c = f.get("class") or "unknown"
        classes[c] = classes.get(c, 0) + 1
    price_signs = sum(n for c, n in classes.items() if "gas" in c or "price" in c or "fuel" in c)
    return 200, {
        "features": len(feats),
        "price_signs": price_signs,
        "classes": classes,
        "credits_used": data.get("totalCreditsUsed"),
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "PumpWatchTest/1.0"

    def log_message(self, fmt, *args):
        sys.stdout.write("%s  %s\n" % (time.strftime("%H:%M:%S"), fmt % args))

    def send_json(self, status, payload):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data)

    def read_json(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n <= 0 or n > 100_000:
            return None
        try:
            return json.loads(self.rfile.read(n))
        except ValueError:
            return None

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        url = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(url.query).items()}
        parts = [p for p in url.path.split("/") if p]
        try:
            if url.path == "/api/health":
                return self.send_json(200, {"ok": True, "time": now_iso()})
            if url.path == "/api/stations":
                lat, lon = float(q["lat"]), float(q["lon"])
                radius_km = min(float(q.get("radius_km", 5)), 50)
                with _db_lock, db() as con:
                    rows = con.execute("SELECT * FROM stations").fetchall()
                    out = [station_payload(con, r, lat, lon) for r in rows]
                out = [s for s in out if s["distance_km"] <= radius_km]
                out.sort(key=lambda s: s["distance_km"])
                return self.send_json(200, {"stations": out})
            if len(parts) == 3 and parts[:2] == ["api", "stations"]:
                with _db_lock, db() as con:
                    row = con.execute("SELECT * FROM stations WHERE id=?", (int(parts[2]),)).fetchone()
                    if not row:
                        return self.send_json(404, {"error": "No such station"})
                    return self.send_json(200, station_payload(con, row))
            if url.path == "/api/hivemapper/check":
                lat, lon = float(q["lat"]), float(q["lon"])
                radius = max(50, min(int(float(q.get("radius_m", 1200))), 1200))
                status, payload = hivemapper_check(lat, lon, radius)
                return self.send_json(status, payload)
        except (KeyError, ValueError):
            return self.send_json(400, {"error": "Missing or bad parameters"})
        self.send_json(404, {"error": "Not found"})

    def do_POST(self):
        if urlparse(self.path).path != "/api/reports":
            return self.send_json(404, {"error": "Not found"})
        body = self.read_json()
        if not isinstance(body, dict):
            return self.send_json(400, {"error": "Send JSON"})
        try:
            lat, lon = float(body["lat"]), float(body["lon"])
        except (KeyError, TypeError, ValueError):
            return self.send_json(400, {"error": "lat and lon are required"})
        prices = {}
        for fuel in FUELS:
            v = body.get(fuel)
            if v in (None, ""):
                continue
            try:
                p = float(v)
            except (TypeError, ValueError):
                return self.send_json(400, {"error": "Bad %s price" % fuel})
            if not 0.5 <= p <= 4.0:
                return self.send_json(400, {"error": "%s price must be in euro per litre, e.g. 1.719" % fuel})
            prices[fuel] = round(p, 3)
        if not prices:
            return self.send_json(400, {"error": "Give at least one price"})
        source = str(body.get("source") or "photo")[:20]
        name = str(body.get("station_name") or "").strip()[:80]

        with _db_lock, db() as con:
            station_id = body.get("station_id")
            row = None
            if station_id:
                row = con.execute("SELECT * FROM stations WHERE id=?", (int(station_id),)).fetchone()
            if row is None:
                best = None
                for r in con.execute("SELECT * FROM stations").fetchall():
                    d = distance_m(lat, lon, r["lat"], r["lon"])
                    if d <= MATCH_RADIUS_M and (best is None or d < best[0]):
                        best = (d, r)
                if best:
                    row = best[1]
            if row is None:
                cur = con.execute(
                    "INSERT INTO stations(name, lat, lon, created_at) VALUES (?,?,?,?)",
                    (name or "Station near %.4f, %.4f" % (lat, lon), lat, lon, now_iso()),
                )
                row = con.execute("SELECT * FROM stations WHERE id=?", (cur.lastrowid,)).fetchone()
            elif name and row["name"].startswith("Station near"):
                con.execute("UPDATE stations SET name=? WHERE id=?", (name, row["id"]))
                row = con.execute("SELECT * FROM stations WHERE id=?", (row["id"],)).fetchone()
            for fuel, p in prices.items():
                con.execute(
                    "INSERT INTO reports(station_id, fuel, price, source, reported_at) VALUES (?,?,?,?,?)",
                    (row["id"], fuel, p, source, now_iso()),
                )
            return self.send_json(201, station_payload(con, row, lat, lon))


def lan_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def main():
    ap = argparse.ArgumentParser(description="PumpWatch test server")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--demo", action="store_true", help="add demo stations around Dublin")
    args = ap.parse_args()
    init_db(args.demo)
    srv = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    print("")
    print("PumpWatch test server is running.")
    print("In the app, open Settings > Server address and enter:")
    print("    http://%s:%d" % (lan_ip(), args.port))
    print("Bee Maps key: %s" % ("found" if load_beemaps_key() else "not set (Hivemapper check disabled)"))
    print("Press Ctrl+C to stop.\n")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
