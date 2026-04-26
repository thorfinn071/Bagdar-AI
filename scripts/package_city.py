
import argparse
import json
import os
import zipfile
from datetime import datetime, timezone


def package_city(city_id, graph_path, poi_path, gtfs_path, output_dir, manifest_path,
                 city_name='', city_name_kk='', base_url='', version=1):
    os.makedirs(output_dir, exist_ok=True)
    zip_name = f"{city_id}.zip"
    zip_path = os.path.join(output_dir, zip_name)
    updated_at = int(datetime.now(timezone.utc).timestamp() * 1000)

    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
        zf.write(graph_path, 'graph.bin')
        zf.write(poi_path, 'poi.db')
        if gtfs_path and os.path.exists(gtfs_path):
            zf.write(gtfs_path, 'gtfs.db')

    zip_size = os.path.getsize(zip_path)
    print(f"Created {zip_path}: {zip_size / 1024 / 1024:.1f} MB")

    manifest = {'manifestVersion': 1, 'baseUrl': base_url, 'packages': []}
    if os.path.exists(manifest_path):
        with open(manifest_path, 'r', encoding='utf-8') as f:
            manifest = json.load(f)

    packages = manifest.get('packages', [])
    existing = [p for p in packages if p.get('cityId') != city_id]

    pkg = {
        'cityId': city_id,
        'name': city_name or city_id,
        'nameKk': city_name_kk,
        'sizeBytes': zip_size,
        'version': version,
        'downloadUrl': f"{base_url}/{zip_name}" if base_url else zip_name,
        'updatedAt': updated_at,
    }
    existing.append(pkg)

    manifest['packages'] = existing
    with open(manifest_path, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)

    print(f"Updated {manifest_path}: {len(existing)} packages")


def main():
    parser = argparse.ArgumentParser(description='Package city map data')
    parser.add_argument('city_id', help='City identifier (e.g. astana)')
    parser.add_argument('graph', help='Path to graph.bin')
    parser.add_argument('poi', help='Path to poi.db')
    parser.add_argument('--gtfs', help='Path to gtfs.db', default=None)
    parser.add_argument('-o', '--output', default='output/', help='Output directory')
    parser.add_argument('--manifest', default='output/map_packages.json',
                        help='Path to manifest JSON')
    parser.add_argument('--name', default='', help='City name (Russian)')
    parser.add_argument('--name-kk', default='', help='City name (Kazakh)')
    parser.add_argument('--base-url', default='', help='Base download URL')
    parser.add_argument('--version', type=int, default=1, help='Package version')

    args = parser.parse_args()
    package_city(
        args.city_id, args.graph, args.poi, args.gtfs, args.output,
        args.manifest, args.name, args.name_kk, args.base_url, args.version,
    )


if __name__ == '__main__':
    main()
