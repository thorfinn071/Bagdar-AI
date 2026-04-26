
"""
GTFS zip → SQLite database for Bagdar offline transit info.

Usage:
    python build_gtfs_db.py input_gtfs.zip output/gtfs.db

Tables:
    routes(route_id, route_number, route_name, route_type,
           start_time, end_time, interval_minutes)
    stops(stop_id, name, name_kk, lat, lng)
    trips(trip_id, route_id, direction_id, service_id)
    stop_times(trip_id, stop_id, arrival_time, departure_time, stop_sequence)
    stop_routes(stop_id, route_id)  -- junction table
"""

import csv
import io
import sqlite3
import sys
import zipfile
from collections import defaultdict


GTFS_FILES = [
    'routes.txt',
    'stops.txt',
    'trips.txt',
    'stop_times.txt',
    'frequencies.txt',
]


def resolve_member_name(zf, filename):
    if filename in zf.namelist():
        return filename
    suffix = '/' + filename
    for name in zf.namelist():
        if name.endswith(suffix):
            return name
    return None


def read_csv_from_zip(zf, filename):
    try:
        member_name = resolve_member_name(zf, filename)
        if member_name is None:
            raise KeyError(filename)
        encodings = ('utf-8-sig', 'utf-8', 'cp1251', 'windows-1251', 'cp1252', 'latin1')
        last_error = None
        for encoding in encodings:
            try:
                with zf.open(member_name) as f:
                    raw = f.read()
                text = raw.decode(encoding)
                sample = text[:4096]
                try:
                    dialect = csv.Sniffer().sniff(sample, delimiters=',\t;|')
                except csv.Error:
                    dialect = csv.excel_tab if '\t' in sample else csv.excel
                return list(csv.DictReader(io.StringIO(text), dialect=dialect))
            except UnicodeDecodeError as exc:
                last_error = exc
                continue
        if last_error is not None:
            raise last_error
    except KeyError:
        print(f"  Warning: {filename} not found in GTFS zip")
        return []


def build_db(gtfs_zip_path, output_path):
    zf = zipfile.ZipFile(gtfs_zip_path, 'r')

    routes_csv = read_csv_from_zip(zf, 'routes.txt')
    stops_csv = read_csv_from_zip(zf, 'stops.txt')
    trips_csv = read_csv_from_zip(zf, 'trips.txt')
    stop_times_csv = read_csv_from_zip(zf, 'stop_times.txt')
    frequencies_csv = read_csv_from_zip(zf, 'frequencies.txt')

    conn = sqlite3.connect(output_path)
    c = conn.cursor()

    c.execute('''CREATE TABLE IF NOT EXISTS routes (
        route_id TEXT PRIMARY KEY,
        route_number TEXT NOT NULL,
        route_name TEXT DEFAULT '',
        route_type TEXT DEFAULT 'bus',
        start_time TEXT DEFAULT '',
        end_time TEXT DEFAULT '',
        interval_minutes INTEGER DEFAULT 0
    )''')

    c.execute('''CREATE TABLE IF NOT EXISTS stops (
        stop_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        name_kk TEXT DEFAULT '',
        lat REAL NOT NULL,
        lng REAL NOT NULL
    )''')

    c.execute('''CREATE INDEX IF NOT EXISTS idx_stops_lat ON stops(lat)''')
    c.execute('''CREATE INDEX IF NOT EXISTS idx_stops_lng ON stops(lng)''')

    c.execute('''CREATE TABLE IF NOT EXISTS trips (
        trip_id TEXT PRIMARY KEY,
        route_id TEXT NOT NULL,
        direction_id INTEGER DEFAULT 0,
        service_id TEXT DEFAULT ''
    )''')

    c.execute('''CREATE TABLE IF NOT EXISTS stop_times (
        trip_id TEXT NOT NULL,
        stop_id TEXT NOT NULL,
        arrival_time TEXT DEFAULT '',
        departure_time TEXT DEFAULT '',
        stop_sequence INTEGER DEFAULT 0
    )''')

    c.execute('''CREATE INDEX IF NOT EXISTS idx_st_trip ON stop_times(trip_id)''')
    c.execute('''CREATE INDEX IF NOT EXISTS idx_st_stop ON stop_times(stop_id)''')

    c.execute('''CREATE TABLE IF NOT EXISTS stop_routes (
        stop_id TEXT NOT NULL,
        route_id TEXT NOT NULL,
        PRIMARY KEY (stop_id, route_id)
    )''')

    freq_map = defaultdict(lambda: {'start': '', 'end': '', 'interval': 0})
    for row in frequencies_csv:
        tid = row.get('trip_id', '')
        start = row.get('start_time', '')
        end = row.get('end_time', '')
        headway = int(row.get('headway_secs', '0') or '0')
        if tid:
            freq_map[tid] = {
                'start': start,
                'end': end,
                'interval': headway // 60 if headway else 0,
            }

    trip_route_map = {}
    for row in trips_csv:
        tid = row.get('trip_id', '')
        rid = row.get('route_id', '')
        trip_route_map[tid] = rid

    route_freq = {}
    for tid, rid in trip_route_map.items():
        if tid in freq_map and rid not in route_freq:
            route_freq[rid] = freq_map[tid]

    ROUTE_TYPES = {'0': 'tram', '1': 'metro', '2': 'rail', '3': 'bus', '4': 'ferry'}

    print(f"  Inserting {len(routes_csv)} routes...")
    for row in routes_csv:
        rid = row.get('route_id', '')
        short_name = row.get('route_short_name', '')
        long_name = row.get('route_long_name', '')
        rtype = ROUTE_TYPES.get(row.get('route_type', '3'), 'bus')
        freq = route_freq.get(rid, {'start': '', 'end': '', 'interval': 0})
        c.execute(
            'INSERT OR REPLACE INTO routes VALUES (?,?,?,?,?,?,?)',
            (rid, short_name, long_name, rtype,
             freq['start'], freq['end'], freq['interval'])
        )

    print(f"  Inserting {len(stops_csv)} stops...")
    for row in stops_csv:
        sid = row.get('stop_id', '')
        name = row.get('stop_name', '')
        lat = float(row.get('stop_lat', '0') or '0')
        lng = float(row.get('stop_lon', '0') or '0')
        if lat == 0 and lng == 0:
            continue
        c.execute(
            'INSERT OR REPLACE INTO stops VALUES (?,?,?,?,?)',
            (sid, name, '', lat, lng)
        )

    print(f"  Inserting {len(trips_csv)} trips...")
    for row in trips_csv:
        c.execute(
            'INSERT OR REPLACE INTO trips VALUES (?,?,?,?)',
            (row.get('trip_id', ''), row.get('route_id', ''),
             int(row.get('direction_id', '0') or '0'),
             row.get('service_id', ''))
        )

    print(f"  Inserting {len(stop_times_csv)} stop_times...")
    batch = []
    for row in stop_times_csv:
        batch.append((
            row.get('trip_id', ''), row.get('stop_id', ''),
            row.get('arrival_time', ''), row.get('departure_time', ''),
            int(row.get('stop_sequence', '0') or '0'),
        ))
    c.executemany('INSERT INTO stop_times VALUES (?,?,?,?,?)', batch)

    print("  Building stop_routes junction...")
    stop_route_set = set()
    for row in stop_times_csv:
        tid = row.get('trip_id', '')
        sid = row.get('stop_id', '')
        rid = trip_route_map.get(tid, '')
        if sid and rid:
            stop_route_set.add((sid, rid))

    c.executemany(
        'INSERT OR IGNORE INTO stop_routes VALUES (?,?)',
        list(stop_route_set)
    )

    conn.commit()
    c.execute('SELECT COUNT(*) FROM routes')
    rc = c.fetchone()[0]
    c.execute('SELECT COUNT(*) FROM stops')
    sc = c.fetchone()[0]
    conn.close()

    print(f"  Written {output_path}: {rc} routes, {sc} stops, "
          f"{len(stop_route_set)} stop-route links")


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <gtfs.zip> <output/gtfs.db>")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]

    print(f"Processing {input_path}...")
    build_db(input_path, output_path)
    print("Done!")


if __name__ == '__main__':
    main()
