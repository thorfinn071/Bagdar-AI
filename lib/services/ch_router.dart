import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

import '../models/nav_models.dart';
import '../models/routing_graph.dart';

class _DijkstraEntry implements Comparable<_DijkstraEntry> {
  final int nodeId;
  final double dist;

  const _DijkstraEntry(this.nodeId, this.dist);

  @override
  int compareTo(_DijkstraEntry other) => dist.compareTo(other.dist);
}

class CHRouter {
  CHGraph? _graph;

  bool get isReady => _graph != null;

  static const double _walkSpeedMps = 1.2;

  Future<void> loadGraph(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Graph file not found', path);
    }

    final bytes = await file.readAsBytes();
    _graph = await compute(_parseGraph, bytes);
    debugPrint(
      'CHRouter: loaded ${_graph!.nodeCount} nodes, ${_graph!.edgeCount} edges',
    );
  }

  static CHGraph _parseGraph(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    int offset = 0;

    final magic = data.getUint32(offset, Endian.little);
    offset += 4;
    final version = data.getUint32(offset, Endian.little);
    offset += 4;
    final nodeCount = data.getUint32(offset, Endian.little);
    offset += 4;
    final fwdEdgeCount = data.getUint32(offset, Endian.little);
    offset += 4;
    final bwdEdgeCount = data.getUint32(offset, Endian.little);
    offset += 4;
    final streetNameCount = data.getUint32(offset, Endian.little);
    offset += 4;
    final minLat = data.getFloat64(offset, Endian.little);
    offset += 8;
    final maxLat = data.getFloat64(offset, Endian.little);
    offset += 8;
    final minLng = data.getFloat64(offset, Endian.little);
    offset += 8;
    final maxLng = data.getFloat64(offset, Endian.little);
    offset += 8;

    final header = CHGraphHeader(
      magic: magic,
      version: version,
      nodeCount: nodeCount,
      forwardEdgeCount: fwdEdgeCount,
      backwardEdgeCount: bwdEdgeCount,
      streetNameCount: streetNameCount,
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
    );

    if (!header.isValid) {
      throw FormatException(
        'Invalid graph: magic=0x${magic.toRadixString(16)}, version=$version',
      );
    }

    final nodes = List<CHNode>.generate(nodeCount, (i) {
      final lat = data.getFloat64(offset, Endian.little);
      offset += 8;
      final lng = data.getFloat64(offset, Endian.little);
      offset += 8;
      final level = data.getUint32(offset, Endian.little);
      offset += 4;
      return CHNode(id: i, lat: lat, lng: lng, level: level);
    });

    final forwardOffsets = List<int>.generate(nodeCount + 1, (i) {
      final v = data.getUint32(offset, Endian.little);
      offset += 4;
      return v;
    });

    final backwardOffsets = List<int>.generate(nodeCount + 1, (i) {
      final v = data.getUint32(offset, Endian.little);
      offset += 4;
      return v;
    });

    final forwardEdges = List<CHEdge>.generate(fwdEdgeCount, (_) {
      final edge = _readEdge(data, offset);
      offset += _edgeByteSize;
      return edge;
    });

    final backwardEdges = List<CHEdge>.generate(bwdEdgeCount, (_) {
      final edge = _readEdge(data, offset);
      offset += _edgeByteSize;
      return edge;
    });

    final streetNames = <String>[];
    for (int i = 0; i < streetNameCount; i++) {
      final len = data.getUint16(offset, Endian.little);
      offset += 2;
      final nameBytes = bytes.sublist(offset, offset + len);
      streetNames.add(String.fromCharCodes(nameBytes));
      offset += len;
    }

    return CHGraph(
      nodes: nodes,
      forwardEdges: forwardEdges,
      backwardEdges: backwardEdges,
      forwardOffsets: forwardOffsets,
      backwardOffsets: backwardOffsets,
      streetNames: streetNames,
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
    );
  }

  static const int _edgeByteSize = 37;

  static CHEdge _readEdge(ByteData data, int offset) {
    final sourceId = data.getUint32(offset, Endian.little);
    offset += 4;
    final targetId = data.getUint32(offset, Endian.little);
    offset += 4;
    final weight = data.getFloat32(offset, Endian.little);
    offset += 4;
    final distanceMeters = data.getFloat32(offset, Endian.little);
    offset += 4;
    final streetNameIndex = data.getInt32(offset, Endian.little);
    offset += 4;
    final flags = data.getUint8(offset);
    offset += 1;
    final surfaceRaw = data.getUint8(offset);
    offset += 1;
    final highwayRaw = data.getUint8(offset);
    offset += 1;
    final accessFlags = data.getUint8(offset);
    offset += 1;
    final isShortcut = (flags & 0x01) != 0;
    int? shortcutMiddle;
    if (isShortcut) {
      shortcutMiddle = data.getUint32(offset, Endian.little);
    }
    offset += 4;

    final surface = surfaceRaw < SurfaceType.values.length
        ? SurfaceType.values[surfaceRaw]
        : SurfaceType.unknown;
    final highway = highwayRaw < HighwayType.values.length
        ? HighwayType.values[highwayRaw]
        : HighwayType.unknown;

    return CHEdge(
      sourceId: sourceId,
      targetId: targetId,
      weight: weight.toDouble(),
      distanceMeters: distanceMeters.toDouble(),
      streetNameIndex: streetNameIndex,
      accessibility: AccessibilityInfo(
        surface: surface,
        highway: highway,
        tactilePaving: (accessFlags & 0x01) != 0,
        sidewalk: (accessFlags & 0x02) != 0,
        lit: (accessFlags & 0x04) != 0,
        wheelchair: (accessFlags & 0x08) != 0,
      ),
      isShortcut: isShortcut,
      
      shortcutMiddleNode: shortcutMiddle,
    );
  }

  NavRoute? findRoute(
    double fromLat,
    double fromLng,
    double toLat,
    double toLng, {
    String destinationName = '',
  }) {
    if (_graph == null) return null;
    final g = _graph!;

    final sourceId = g.findNearestNode(fromLat, fromLng);
    final targetId = g.findNearestNode(toLat, toLng);

    if (sourceId == targetId) {
      return NavRoute(
        steps: [
          RouteStep(
            instruction: '',
            distanceMeters: 0,
            durationSeconds: 0,
            startLat: fromLat,
            startLng: fromLng,
            endLat: toLat,
            endLng: toLng,
            maneuver: Maneuver.arrive,
          ),
        ],
        totalDistanceMeters: 0,
        totalDurationSeconds: 0,
        destinationName: destinationName,
      );
    }

    final path = _bidirectionalDijkstra(g, sourceId, targetId);
    if (path == null || path.isEmpty) return null;

    final expandedPath = _expandShortcuts(g, path);
    return _buildNavRoute(g, expandedPath, destinationName);
  }

  List<CHEdge>? _bidirectionalDijkstra(CHGraph g, int source, int target) {
    final fwdDist = HashMap<int, double>();
    final bwdDist = HashMap<int, double>();
    final fwdPrev = HashMap<int, int>();
    final bwdPrev = HashMap<int, int>();
    final fwdEdge = HashMap<int, CHEdge>();
    final bwdEdge = HashMap<int, CHEdge>();
    final fwdSettled = HashSet<int>();
    final bwdSettled = HashSet<int>();

    final fwdPQ = SplayTreeSet<_DijkstraEntry>((a, b) {
      final c = a.dist.compareTo(b.dist);
      return c != 0 ? c : a.nodeId.compareTo(b.nodeId);
    });
    final bwdPQ = SplayTreeSet<_DijkstraEntry>((a, b) {
      final c = a.dist.compareTo(b.dist);
      return c != 0 ? c : a.nodeId.compareTo(b.nodeId);
    });

    fwdDist[source] = 0.0;
    bwdDist[target] = 0.0;
    fwdPQ.add(_DijkstraEntry(source, 0.0));
    bwdPQ.add(_DijkstraEntry(target, 0.0));

    double bestDist = double.infinity;
    int meetNode = -1;

    
    while (fwdPQ.isNotEmpty || bwdPQ.isNotEmpty) {
      if (fwdPQ.isNotEmpty) {
        final cur = fwdPQ.first;
        fwdPQ.remove(cur);

        if (cur.dist > bestDist) {
          fwdPQ.clear();
        } else if (!fwdSettled.contains(cur.nodeId)) {
          fwdSettled.add(cur.nodeId);

          if (bwdDist.containsKey(cur.nodeId)) {
            final total = cur.dist + bwdDist[cur.nodeId]!;
            if (total < bestDist) {
              bestDist = total;
              meetNode = cur.nodeId;
            }
          }

          for (final edge in g.outEdges(cur.nodeId)) {
            if (g.nodes[edge.targetId].level < g.nodes[cur.nodeId].level &&
                edge.targetId != target) {
              continue;
            }
            final newDist = cur.dist + edge.weight;
            if (newDist < (fwdDist[edge.targetId] ?? double.infinity)) {
              fwdDist[edge.targetId] = newDist;
              fwdPrev[edge.targetId] = cur.nodeId;
              fwdEdge[edge.targetId] = edge;
              fwdPQ.add(_DijkstraEntry(edge.targetId, newDist));
            }
          }
        }
      }

      if (bwdPQ.isNotEmpty) {
        final cur = bwdPQ.first;
        bwdPQ.remove(cur);

        if (cur.dist > bestDist) {
          bwdPQ.clear();
        } else if (!bwdSettled.contains(cur.nodeId)) {
          bwdSettled.add(cur.nodeId);

          if (fwdDist.containsKey(cur.nodeId)) {
            final total = cur.dist + fwdDist[cur.nodeId]!;
            if (total < bestDist) {
              bestDist = total;
              meetNode = cur.nodeId;
            }
          }

          for (final edge in g.inEdges(cur.nodeId)) {
            if (g.nodes[edge.sourceId].level < g.nodes[cur.nodeId].level &&
                edge.sourceId != source) {
              continue;
            }
            final newDist = cur.dist + edge.weight;
            if (newDist < (bwdDist[edge.sourceId] ?? double.infinity)) {
              bwdDist[edge.sourceId] = newDist;
              bwdPrev[edge.sourceId] = cur.nodeId;
              bwdEdge[edge.sourceId] = edge;
              bwdPQ.add(_DijkstraEntry(edge.sourceId, newDist));
            }
          }
        }
      }
    }

    if (meetNode == -1) return null;

    final edges = <CHEdge>[];

    int cur = meetNode;
    final fwdPath = <CHEdge>[];
    while (cur != source) {
      final e = fwdEdge[cur];
      if (e == null) return null;
      fwdPath.add(e);
      cur = fwdPrev[cur]!;
    }
    edges.addAll(fwdPath.reversed);

    cur = meetNode;
    while (cur != target) {
      final e = bwdEdge[cur];
      if (e == null) return null;
      edges.add(e);
      cur = bwdPrev[cur]!;
    }

    return edges;
  }

  static const int _maxShortcutDepth = 64;

  List<CHEdge> _expandShortcuts(CHGraph g, List<CHEdge> path) {
    final expanded = <CHEdge>[];
    for (final edge in path) {
      if (edge.isShortcut && edge.shortcutMiddleNode != null) {
        _expandSingleShortcut(g, edge, expanded, 0);
      } else {
        expanded.add(edge);
      }
    }
    return expanded;
  }

  void _expandSingleShortcut(
    CHGraph g,
    CHEdge shortcut,
    List<CHEdge> result,
    int depth,
  ) {
    if (depth >= _maxShortcutDepth) {
      result.add(shortcut);
      return;
    }

    final mid = shortcut.shortcutMiddleNode!;

    CHEdge? firstHalf;
    CHEdge? secondHalf;
    double bestDiff = double.infinity;

    for (final e1 in g.outEdges(shortcut.sourceId)) {
      if (e1.targetId != mid) continue;
      for (final e2 in g.outEdges(mid)) {
        if (e2.targetId != shortcut.targetId) continue;

        final diff = (e1.weight + e2.weight - shortcut.weight).abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          firstHalf = e1;
          secondHalf = e2;
        }
      }
    }

    if (firstHalf == null || secondHalf == null) {
      result.add(shortcut);
      return;
    }

    if (firstHalf.isShortcut && firstHalf.shortcutMiddleNode != null) {
      _expandSingleShortcut(g, firstHalf, result, depth + 1);
    } else {
      result.add(firstHalf);
    }

    if (secondHalf.isShortcut && secondHalf.shortcutMiddleNode != null) {
      _expandSingleShortcut(g, secondHalf, result, depth + 1);
    } else {
      result.add(secondHalf);
    }
  }

  NavRoute _buildNavRoute(
    CHGraph g,
    List<CHEdge> edges,
    String destinationName,
  ) {
    if (edges.isEmpty) {
      return NavRoute(
        steps: [],
        totalDistanceMeters: 0,
        totalDurationSeconds: 0,
        destinationName: destinationName,
      );
    }

    final steps = <RouteStep>[];
    double totalDist = 0;

    int segStart = 0;
    for (int i = 1; i <= edges.length; i++) {
      final bool newSegment =
          i == edges.length ||
          edges[i].streetNameIndex != edges[segStart].streetNameIndex ||
          _shouldSplit(g, edges[i - 1], edges[i]);

      if (newSegment) {
        double segDist = 0;
        for (int j = segStart; j < i; j++) {
          segDist += edges[j].distanceMeters;
        }

        final firstEdge = edges[segStart];
        final lastEdge = edges[i - 1];
        final srcNode = g.nodes[firstEdge.sourceId];
        final tgtNode = g.nodes[lastEdge.targetId];

        Maneuver maneuver;
        if (segStart == 0) {
          maneuver = Maneuver.straight;
        } else {
          maneuver = _computeManeuver(g, edges[segStart - 1], firstEdge);
        }

        
        if (i == edges.length && segDist < 20) {
          maneuver = Maneuver.arrive;
        }

        final streetName = g.streetName(firstEdge.streetNameIndex);
        final instruction = _buildInstruction(maneuver, streetName);
        final durationSec = (segDist / _walkSpeedMps).round();

        steps.add(
          RouteStep(
            instruction: instruction,
            distanceMeters: segDist.round(),
            durationSeconds: durationSec,
            startLat: srcNode.lat,
            startLng: srcNode.lng,
            endLat: tgtNode.lat,
            endLng: tgtNode.lng,
            maneuver: maneuver,
          ),
        );

        totalDist += segDist;
        segStart = i;
      }
    }

    final totalDuration = (totalDist / _walkSpeedMps).round();

    return NavRoute(
      steps: steps,
      totalDistanceMeters: totalDist.round(),
      totalDurationSeconds: totalDuration,
      destinationName: destinationName,
    );
  }

  bool _shouldSplit(CHGraph g, CHEdge prev, CHEdge next) {
    final m = _computeManeuver(g, prev, next);
    return m != Maneuver.straight;
  }

  Maneuver _computeManeuver(CHGraph g, CHEdge prev, CHEdge next) {
    final p1 = g.nodes[prev.sourceId];
    final p2 = g.nodes[prev.targetId];
    final p3 = g.nodes[next.targetId];

    final bearing1 = _bearing(p1.lat, p1.lng, p2.lat, p2.lng);
    final bearing2 = _bearing(p2.lat, p2.lng, p3.lat, p3.lng);

    final angle = ((bearing2 - bearing1) % 360 + 360) % 360;
    return maneuverFromAngle(angle);
  }

  static double _bearing(double lat1, double lng1, double lat2, double lng2) {
    final dLng = _toRad(lng2 - lng1);
    final y = sin(dLng) * cos(_toRad(lat2));
    final x =
        cos(_toRad(lat1)) * sin(_toRad(lat2)) -
        sin(_toRad(lat1)) * cos(_toRad(lat2)) * cos(dLng);
    return (_toDeg(atan2(y, x)) + 360) % 360;
  }

  static double _toRad(double deg) => deg * pi / 180;
  static double _toDeg(double rad) => rad * 180 / pi;

  String _buildInstruction(Maneuver m, String streetName) {
    final dir = _maneuverVerb(m);
    if (streetName.isEmpty) return dir;
    return '$dir, $streetName';
  }

  String _maneuverVerb(Maneuver m) {
    switch (m) {
      case Maneuver.straight:
        return 'Прямо';
      case Maneuver.turnLeft:
        return 'Поверните налево';
      case Maneuver.turnRight:
        return 'Поверните направо';
      case Maneuver.slightLeft:
        return 'Левее';
      case Maneuver.slightRight:
        return 'Правее';
      case Maneuver.uTurn:
        return 'Развернитесь';
      case Maneuver.arrive:
        return 'Вы прибыли';
    }
  }

  void dispose() {
    _graph = null;
  }
}
