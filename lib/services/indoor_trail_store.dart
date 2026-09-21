import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/indoor_trail.dart';
import 'field_logger.dart';

/// On-disk persistence for indoor trails. One file per trail under
/// `<docs>/bagdar_indoor_trails/<id>.json`. Never uploaded; deletable by
/// the user via voice command or settings UI.
class IndoorTrailStore {
  IndoorTrailStore._();

  static final IndoorTrailStore instance = IndoorTrailStore._();

  /// Hard cap on the number of trails the user can have stored at any
  /// one time. Soft enforcement: when exceeded, `save()` deletes the
  /// oldest trail. Keeps storage bounded without bothering the user.
  static const int kMaxTrails = 20;

  static const String _kDirName = 'bagdar_indoor_trails';

  Directory? _dirCached;

  Future<Directory> _dir() async {
    final cached = _dirCached;
    if (cached != null) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_kDirName');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _dirCached = dir;
    return dir;
  }

  /// List all stored trails, newest first. Failed-to-parse files are
  /// skipped silently so a corrupted record never crashes the app.
  Future<List<IndoorTrail>> list() async {
    try {
      final dir = await _dir();
      final files = dir.listSync().whereType<File>().toList();
      final results = <IndoorTrail>[];
      for (final f in files) {
        if (!f.path.endsWith('.json')) continue;
        try {
          final raw = await f.readAsString();
          results.add(IndoorTrail.decode(raw));
        } catch (e) {
          debugPrint('IndoorTrailStore: skipping corrupt file ${f.path} ($e)');
        }
      }
      results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return results;
    } catch (e) {
      debugPrint('IndoorTrailStore.list error: $e');
      return const [];
    }
  }

  /// Look up a trail by its id. Returns null if not found.
  Future<IndoorTrail?> getById(String id) async {
    try {
      final dir = await _dir();
      final file = File('${dir.path}/$id.json');
      if (!file.existsSync()) return null;
      final raw = await file.readAsString();
      return IndoorTrail.decode(raw);
    } catch (e) {
      debugPrint('IndoorTrailStore.getById error: $e');
      return null;
    }
  }

  /// Find the most recent trail whose user-facing [name] matches
  /// case-insensitively. Used by the voice command "go to {name}".
  Future<IndoorTrail?> findByName(String name) async {
    final needle = name.trim().toLowerCase();
    if (needle.isEmpty) return null;
    final all = await list();
    for (final t in all) {
      if (t.name.trim().toLowerCase() == needle) return t;
    }

    for (final t in all) {
      if (t.name.trim().toLowerCase().contains(needle)) return t;
    }
    return null;
  }

  /// Persist a trail. Enforces the [kMaxTrails] cap by deleting the
  /// oldest record(s) when needed. Returns the saved trail on success.
  Future<IndoorTrail?> save(IndoorTrail trail) async {
    try {
      final dir = await _dir();
      final file = File('${dir.path}/${trail.id}.json');
      await file.writeAsString(trail.encode(), flush: true);

      final all = await list();
      if (all.length > kMaxTrails) {
        final excess = all.length - kMaxTrails;
        final toRemove = all.skip(kMaxTrails).take(excess).toList();
        for (final t in toRemove) {
          await delete(t.id);
        }
      }

      FieldLogger.instance.logIndoorTrail(
        'saved',
        data: {'id': trail.id, 'samples': trail.sampleCount},
      );
      return trail;
    } catch (e) {
      debugPrint('IndoorTrailStore.save error: $e');
      FieldLogger.instance.logIndoorTrail(
        'save_failed',
        data: {'id': trail.id, 'error': e.toString()},
      );
      return null;
    }
  }

  /// Delete the trail with the given [id]. Idempotent.
  Future<bool> delete(String id) async {
    try {
      final dir = await _dir();
      final file = File('${dir.path}/$id.json');
      if (file.existsSync()) {
        await file.delete();
        FieldLogger.instance.logIndoorTrail('deleted', data: {'id': id});
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('IndoorTrailStore.delete error: $e');
      return false;
    }
  }

  /// Delete *every* stored trail. Provided for settings UI "forget all
  /// indoor trails" affordance and for tests.
  Future<int> clear() async {
    var n = 0;
    try {
      final dir = await _dir();
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.json')) continue;
        try {
          await f.delete();
          n++;
        } catch (_) {}
      }
      FieldLogger.instance.logIndoorTrail('cleared', data: {'count': n});
    } catch (e) {
      debugPrint('IndoorTrailStore.clear error: $e');
    }
    return n;
  }

  @visibleForTesting
  void debugSetDir(Directory dir) {
    _dirCached = dir;
  }
}
