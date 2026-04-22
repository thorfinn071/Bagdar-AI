#!/usr/bin/env python3
"""
OSM .pbf → binary CH graph for Bagdar offline routing.

Usage:
    pip install osmium networkx
    python build_ch_graph.py input.osm.pbf output/graph.bin

Binary format (little-endian):
    Header (72 bytes):
        u32 magic (0x56474348)
        u32 version (1)
        u32 node_count
        u32 forward_edge_count
        u32 backward_edge_count
        u32 street_name_count
        f64 min_lat, max_lat, min_lng, max_lng

    Nodes (node_count × 20 bytes each):
        f64 lat, f64 lng, u32 level

    Forward offsets ((node_count+1) × 4 bytes):
        u32 offset

    Backward offsets ((node_count+1) × 4 bytes):
        u32 offset

    Forward edges (forward_edge_count × 37 bytes each):
        u32 source, u32 target, f32 weight, f32 distance_m,
        i32 street_name_idx, u8 flags, u8 surface, u8 highway, u8 access_flags,
        u32 shortcut_middle (0xFFFFFFFF if not shortcut)

    Backward edges (same format)

    Street names:
        For each: u16 len + len bytes (UTF-8)
"""

import argparse
import struct
import sys
import math
from collections import defaultdict

import osmium


HIGHWAY_PEDESTRIAN = {
    'footway', 'pedestrian', 'path', 'residential', 'living_street',
    'service', 'tertiary', 'secondary', 'primary', 'steps',
    'cycleway', 'unclassified', 'track',
}

HIGHWAY_BLOCKED = {'motorway', 'motorway_link', 'trunk', 'trunk_link'}

SURFACE_MAP = {
    'asphalt': 0, 'concrete': 1, 'paving_stones': 2, 'gravel': 3,
    'dirt': 4, 'grass': 5, 'sand': 6, 'unpaved': 7,
}

HIGHWAY_MAP = {
    'footway': 0, 'pedestrian': 1, 'path': 2, 'residential': 3,
    'living_street': 4, 'service': 5, 'tertiary': 6, 'secondary': 7,
    'primary': 8, 'trunk': 9, 'motorway': 10, 'steps': 11,
    'cycleway': 12, 'unclassified': 13,
}

WEIGHT_HIGHWAY = {
    'footway': 0.8, 'pedestrian': 0.8, 'path': 0.9, 'living_street': 0.9,
    'residential': 1.0, 'service': 1.0, 'steps': 1.4, 'tertiary': 1.1,
    'secondary': 1.3, 'primary': 1.5, 'cycleway': 1.2, 'unclassified': 1.0,
    'track': 1.3,
}

WEIGHT_SURFACE = {
    'asphalt': 1.0, 'concrete': 1.0, 'paving_stones': 1.0,
    'gravel': 1.3, 'dirt': 1.5, 'grass': 1.5, 'sand': 1.8, 'unpaved': 1.4,
}


def in_bbox(lat, lng, bbox):
    if bbox is None:
        return True
    min_lat, max_lat, min_lng, max_lng = bbox
    return min_lat <= lat <= max_lat and min_lng <= lng <= max_lng


def haversine(lat1, lng1, lat2, lng2):
    R = 6371000.0
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = (math.sin(dlat / 2) ** 2 +
         math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) *
         math.sin(dlng / 2) ** 2)
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


class WayHandler(osmium.SimpleHandler):
    def __init__(self, bbox=None):
        super().__init__()
        self.bbox = bbox
        self.nodes = {}
        self.edges = []
        self.street_names = {}
        self.street_name_list = []

    def _get_street_idx(self, name):
        if not name:
            return -1
        if name not in self.street_names:
            idx = len(self.street_name_list)
            self.street_names[name] = idx
            self.street_name_list.append(name)
        return self.street_names[name]

    def way(self, w):
        tags = {t.k: t.v for t in w.tags}
        hw = tags.get('highway', '')
        if hw not in HIGHWAY_PEDESTRIAN:
            return
        if tags.get('access') == 'private':
            return

        node_refs = []
        touches_bbox = self.bbox is None
        for n in w.nodes:
            if n.location.valid():
                self.nodes[n.ref] = (n.location.lat, n.location.lon)
                node_refs.append(n.ref)
                if not touches_bbox and in_bbox(n.location.lat, n.location.lon, self.bbox):
                    touches_bbox = True

        if self.bbox is not None and not touches_bbox:
            return

        if len(node_refs) < 2:
            return

        surface = tags.get('surface', '')
        tactile = tags.get('tactile_paving', '') == 'yes'
        sidewalk = tags.get('sidewalk', '') in ('yes', 'both', 'left', 'right')
        lit = tags.get('lit', '') == 'yes'
        wheelchair = tags.get('wheelchair', '') == 'yes'
        name = tags.get('name', '')
        oneway = tags.get('oneway', '') in ('yes', '1', 'true')

        street_idx = self._get_street_idx(name)
        surface_val = SURFACE_MAP.get(surface, 8)
        highway_val = HIGHWAY_MAP.get(hw, 14)

        access_flags = 0
        if tactile:
            access_flags |= 0x01
        if sidewalk:
            access_flags |= 0x02
        if lit:
            access_flags |= 0x04
        if wheelchair:
            access_flags |= 0x08

        hw_weight = WEIGHT_HIGHWAY.get(hw, 1.0)
        surf_weight = WEIGHT_SURFACE.get(surface, 1.05)
        base_multiplier = hw_weight * surf_weight
        if tactile:
            base_multiplier *= 0.85
        if sidewalk:
            base_multiplier *= 0.9
        if lit:
            base_multiplier *= 0.95

        for i in range(len(node_refs) - 1):
            n1 = node_refs[i]
            n2 = node_refs[i + 1]
            lat1, lng1 = self.nodes[n1]
            lat2, lng2 = self.nodes[n2]
            dist = haversine(lat1, lng1, lat2, lng2)
            weight = dist * base_multiplier

            edge_data = {
                'weight': weight,
                'distance': dist,
                'street_idx': street_idx,
                'surface': surface_val,
                'highway': highway_val,
                'access_flags': access_flags,
            }

            self.edges.append((n1, n2, edge_data))
            if not oneway:
                self.edges.append((n2, n1, edge_data))


def build_graph(handler):
    used_nodes = set()
    for src, tgt, _ in handler.edges:
        used_nodes.add(src)
        used_nodes.add(tgt)

    node_list = sorted(used_nodes)
    node_remap = {osm_id: idx for idx, osm_id in enumerate(node_list)}

    nodes = {}
    for idx, osm_id in enumerate(node_list):
        lat, lng = handler.nodes[osm_id]
        nodes[idx] = {'lat': lat, 'lng': lng, 'level': 0}

    edges = {}
    for src, tgt, data in handler.edges:
        s = node_remap[src]
        t = node_remap[tgt]
        key = (s, t)
        if key in edges:
            if edges[key]['weight'] > data['weight']:
                edges[key] = {
                    **data,
                    'is_shortcut': False,
                    'shortcut_mid': 0xFFFFFFFF,
                }
        else:
            edges[key] = {
                **data,
                'is_shortcut': False,
                'shortcut_mid': 0xFFFFFFFF,
            }

    return {'nodes': nodes, 'edges': edges}, node_list, handler.street_name_list


def contract_graph(graph):
    print(f"  Contracting {len(graph['nodes'])} nodes...")
    degree_map = defaultdict(int)
    for src, tgt in graph['edges']:
        degree_map[src] += 1
        degree_map[tgt] += 1

    node_order = sorted(graph['nodes'], key=lambda n: (degree_map.get(n, 0), n))
    for level, node in enumerate(node_order):
        graph['nodes'][node]['level'] = level

    print(f"  Contraction done. Edges: {len(graph['edges'])}")
    return graph


def write_binary(graph, node_list, street_names, handler, output_path):
    nodes_data = []
    for i in range(len(node_list)):
        lat = graph['nodes'][i]['lat']
        lng = graph['nodes'][i]['lng']
        level = graph['nodes'][i]['level']
        nodes_data.append((lat, lng, level))

    forward_adj = defaultdict(list)
    backward_adj = defaultdict(list)

    for (u, v), d in graph['edges'].items():
        flags = 0x01 if d.get('is_shortcut', False) else 0x00
        mid = d.get('shortcut_mid', 0xFFFFFFFF)
        edge = (u, v, d['weight'], d['distance'],
                d.get('street_idx', -1), flags,
                d.get('surface', 8), d.get('highway', 14),
                d.get('access_flags', 0), mid)
        forward_adj[u].append(edge)
        backward_adj[v].append(edge)

    n = len(nodes_data)
    fwd_edges = []
    fwd_offsets = [0]
    for i in range(n):
        edges = forward_adj.get(i, [])
        fwd_edges.extend(edges)
        fwd_offsets.append(len(fwd_edges))

    bwd_edges = []
    bwd_offsets = [0]
    for i in range(n):
        edges = backward_adj.get(i, [])
        bwd_edges.extend(edges)
        bwd_offsets.append(len(bwd_edges))

    lats = [nd[0] for nd in nodes_data]
    lngs = [nd[1] for nd in nodes_data]
    min_lat, max_lat = min(lats), max(lats)
    min_lng, max_lng = min(lngs), max(lngs)

    MAGIC = 0x56474348
    VERSION = 1

    with open(output_path, 'wb') as f:
        f.write(struct.pack('<II', MAGIC, VERSION))
        f.write(struct.pack('<I', n))
        f.write(struct.pack('<I', len(fwd_edges)))
        f.write(struct.pack('<I', len(bwd_edges)))
        f.write(struct.pack('<I', len(street_names)))
        f.write(struct.pack('<dddd', min_lat, max_lat, min_lng, max_lng))

        for lat, lng, level in nodes_data:
            f.write(struct.pack('<ddI', lat, lng, level))

        for off in fwd_offsets:
            f.write(struct.pack('<I', off))
        for off in bwd_offsets:
            f.write(struct.pack('<I', off))

        for edge in fwd_edges:
            _write_edge(f, edge)
        for edge in bwd_edges:
            _write_edge(f, edge)

        for name in street_names:
            name_bytes = name.encode('utf-8')
            f.write(struct.pack('<H', len(name_bytes)))
            f.write(name_bytes)

    total_size = sum([
        72,
        n * 20,
        (n + 1) * 4 * 2,
        len(fwd_edges) * 37,
        len(bwd_edges) * 37,
    ])
    print(f"  Written {output_path}: {n} nodes, "
          f"{len(fwd_edges)} fwd edges, {len(bwd_edges)} bwd edges, "
          f"{len(street_names)} street names, ~{total_size // 1024} KB")


def _write_edge(f, edge):
    src, tgt, weight, dist, street_idx, flags, surface, highway, access_flags, mid = edge
    f.write(struct.pack('<II', src, tgt))
    f.write(struct.pack('<f', weight))
    f.write(struct.pack('<f', dist))
    f.write(struct.pack('<i', street_idx))
    f.write(struct.pack('<BBBB', flags, surface, highway, access_flags))
    f.write(struct.pack('<I', mid))


def main():
    parser = argparse.ArgumentParser(description='Build CH graph from OSM PBF')
    parser.add_argument('input', help='Input .osm.pbf file')
    parser.add_argument('output', help='Output .bin file')
    parser.add_argument('--bbox', nargs=4, type=float, metavar=('MIN_LAT', 'MAX_LAT', 'MIN_LNG', 'MAX_LNG'))
    args = parser.parse_args()

    input_path = args.input
    output_path = args.output
    bbox = tuple(args.bbox) if args.bbox else None

    print(f"Reading {input_path}...")
    handler = WayHandler(bbox=bbox)
    handler.apply_file(input_path, locations=True)
    print(f"  Parsed {len(handler.nodes)} nodes, {len(handler.edges)} edges, "
          f"{len(handler.street_name_list)} street names")

    print("Building graph...")
    graph, node_list, street_names = build_graph(handler)
    print(f"  Graph: {len(graph['nodes'])} nodes, {len(graph['edges'])} edges")

    print("Contracting...")
    graph = contract_graph(graph)

    print("Writing binary...")
    write_binary(graph, node_list, street_names, handler, output_path)
    print("Done!")


if __name__ == '__main__':
    main()
