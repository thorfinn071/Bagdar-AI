
"""
OSM .pbf → SQLite POI database with FTS5 for Bagdar offline search.

Usage:
    pip install osmium
    python build_poi_db.py input.osm.pbf output/poi.db

Tables:
    poi(id, name, name_kk, lat, lng, address, category)
    poi_fts(name, name_kk, category)  -- FTS5 virtual table
    transit_stops(id, name, name_kk, lat, lng, routes)
"""

import argparse
import os
import sqlite3
import sys

import osmium


POI_TAGS = {
    'amenity': {
        'pharmacy': 'аптека',
        'hospital': 'больница',
        'clinic': 'клиника',
        'doctors': 'врач',
        'dentist': 'стоматолог',
        'bank': 'банк',
        'atm': 'банкомат',
        'cafe': 'кафе',
        'restaurant': 'ресторан',
        'fast_food': 'фастфуд',
        'school': 'школа',
        'university': 'университет',
        'kindergarten': 'детский сад',
        'library': 'библиотека',
        'post_office': 'почта',
        'police': 'полиция',
        'fire_station': 'пожарная станция',
        'fuel': 'заправка',
        'parking': 'парковка',
        'toilet': 'туалет',
        'marketplace': 'рынок',
        'place_of_worship': 'мечеть',
    },
    'shop': {
        'supermarket': 'супермаркет',
        'convenience': 'магазин',
        'clothes': 'одежда',
        'electronics': 'электроника',
        'bakery': 'пекарня',
        'butcher': 'мясной',
        'greengrocer': 'овощи фрукты',
        'hardware': 'хозтовары',
        'mobile_phone': 'телефоны',
        'optician': 'оптика',
        'shoes': 'обувь',
        'beauty': 'салон красоты',
        'hairdresser': 'парикмахерская',
        'mall': 'торговый центр',
        'department_store': 'универмаг',
    },
    'tourism': {
        'hotel': 'гостиница',
        'museum': 'музей',
        'attraction': 'достопримечательность',
        'viewpoint': 'смотровая площадка',
    },
    'leisure': {
        'park': 'парк',
        'playground': 'детская площадка',
        'sports_centre': 'спорткомплекс',
        'stadium': 'стадион',
        'swimming_pool': 'бассейн',
    },
    'office': {
        'government': 'госучреждение',
    },
}

TRANSIT_TAGS = {'bus_stop', 'tram_stop', 'station', 'halt', 'platform'}


def in_bbox(lat, lng, bbox):
    if bbox is None:
        return True
    min_lat, max_lat, min_lng, max_lng = bbox
    return min_lat <= lat <= max_lat and min_lng <= lng <= max_lng


class POIHandler(osmium.SimpleHandler):
    def __init__(self, bbox=None):
        super().__init__()
        self.bbox = bbox
        self.pois = []
        self.stops = []

    def node(self, n):
        if not n.location.valid():
            return

        tags = {t.k: t.v for t in n.tags}
        lat = n.location.lat
        lng = n.location.lon

        if not in_bbox(lat, lng, self.bbox):
            return

        highway = tags.get('highway', '')
        public_transport = tags.get('public_transport', '')
        railway = tags.get('railway', '')

        if (highway == 'bus_stop' or
                public_transport in TRANSIT_TAGS or
                railway in ('station', 'halt', 'tram_stop')):
            name = tags.get('name', tags.get('name:ru', ''))
            name_kk = tags.get('name:kk', '')
            routes = tags.get('route_ref', '')
            if name:
                self.stops.append((name, name_kk, lat, lng, routes))

        for tag_key, categories in POI_TAGS.items():
            val = tags.get(tag_key, '')
            if val in categories:
                name = tags.get('name', tags.get('name:ru', ''))
                if not name:
                    name = categories[val]
                name_kk = tags.get('name:kk', '')
                address = self._build_address(tags)
                category = categories[val]
                self.pois.append((name, name_kk, lat, lng, address, category))
                break

    def _build_address(self, tags):
        street = tags.get('addr:street', '')
        house = tags.get('addr:housenumber', '')
        if street and house:
            return f"{street}, {house}"
        if street:
            return street
        return ''


def build_db(handler, output_path):
    if os.path.exists(output_path):
        os.remove(output_path)

    conn = sqlite3.connect(output_path)
    c = conn.cursor()

    c.execute('''CREATE TABLE IF NOT EXISTS poi (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        name_kk TEXT DEFAULT '',
        lat REAL NOT NULL,
        lng REAL NOT NULL,
        address TEXT DEFAULT '',
        category TEXT DEFAULT ''
    )''')

    c.execute('''CREATE INDEX IF NOT EXISTS idx_poi_lat ON poi(lat)''')
    c.execute('''CREATE INDEX IF NOT EXISTS idx_poi_lng ON poi(lng)''')

    c.execute('''CREATE VIRTUAL TABLE IF NOT EXISTS poi_fts
        USING fts5(name, name_kk, category, content=poi, content_rowid=id)''')

    c.execute('''CREATE TABLE IF NOT EXISTS transit_stops (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        name_kk TEXT DEFAULT '',
        lat REAL NOT NULL,
        lng REAL NOT NULL,
        routes TEXT DEFAULT ''
    )''')

    c.execute('''CREATE INDEX IF NOT EXISTS idx_stops_lat ON transit_stops(lat)''')
    c.execute('''CREATE INDEX IF NOT EXISTS idx_stops_lng ON transit_stops(lng)''')

    print(f"  Inserting {len(handler.pois)} POIs...")
    c.executemany(
        'INSERT INTO poi (name, name_kk, lat, lng, address, category) VALUES (?,?,?,?,?,?)',
        handler.pois
    )

    c.execute('''INSERT INTO poi_fts(rowid, name, name_kk, category)
        SELECT id, name, name_kk, category FROM poi''')

    print(f"  Inserting {len(handler.stops)} transit stops...")
    c.executemany(
        'INSERT INTO transit_stops (name, name_kk, lat, lng, routes) VALUES (?,?,?,?,?)',
        handler.stops
    )

    conn.commit()

    c.execute('SELECT COUNT(*) FROM poi')
    poi_count = c.fetchone()[0]
    c.execute('SELECT COUNT(*) FROM transit_stops')
    stop_count = c.fetchone()[0]

    conn.close()
    print(f"  Written {output_path}: {poi_count} POIs, {stop_count} transit stops")


def main():
    parser = argparse.ArgumentParser(description='Build POI database from OSM PBF')
    parser.add_argument('input', help='Input .osm.pbf file')
    parser.add_argument('output', help='Output .db file')
    parser.add_argument('--bbox', nargs=4, type=float, metavar=('MIN_LAT', 'MAX_LAT', 'MIN_LNG', 'MAX_LNG'))
    args = parser.parse_args()

    input_path = args.input
    output_path = args.output
    bbox = tuple(args.bbox) if args.bbox else None

    print(f"Reading {input_path}...")
    handler = POIHandler(bbox=bbox)
    handler.apply_file(input_path, locations=True)
    print(f"  Found {len(handler.pois)} POIs, {len(handler.stops)} transit stops")

    print("Building database...")
    build_db(handler, output_path)
    print("Done!")


if __name__ == '__main__':
    main()
