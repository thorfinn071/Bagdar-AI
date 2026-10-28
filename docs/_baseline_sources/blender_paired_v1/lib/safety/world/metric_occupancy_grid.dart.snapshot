import 'local_scene_snapshot.dart';

/// Explicit calibration required before metric world state can be created.
///
/// The grid deliberately has no device-independent default resolution. A
/// caller must supply values backed by a named calibration/benchmark.
class MetricGridCalibration {
  final String calibrationId;
  final int lateralCellCount;
  final int forwardCellCount;
  final double cellSizeMeters;

  const MetricGridCalibration({
    required this.calibrationId,
    required this.lateralCellCount,
    required this.forwardCellCount,
    required this.cellSizeMeters,
  }) : assert(calibrationId != ''),
       assert(lateralCellCount > 0),
       assert(forwardCellCount > 0),
       assert(cellSizeMeters > 0 && cellSizeMeters < double.infinity);

  int get cellCount => lateralCellCount * forwardCellCount;

  bool contains(MetricCellIndex index) =>
      index.lateral >= 0 &&
      index.lateral < lateralCellCount &&
      index.forward >= 0 &&
      index.forward < forwardCellCount;
}

class MetricCellIndex {
  final int lateral;
  final int forward;

  const MetricCellIndex({required this.lateral, required this.forward});

  String get elementId => 'cell:$lateral:$forward';

  static MetricCellIndex? tryParse(String elementId) {
    final parts = elementId.split(':');
    if (parts.length != 3 || parts.first != 'cell') return null;
    final lateral = int.tryParse(parts[1]);
    final forward = int.tryParse(parts[2]);
    if (lateral == null || forward == null) return null;
    return MetricCellIndex(lateral: lateral, forward: forward);
  }
}

/// Immutable metric view. LocalSceneModel owns mutation and temporal decay.
class MetricOccupancyGrid {
  final MetricGridCalibration calibration;
  final List<SceneSpatialElement> cells;

  MetricOccupancyGrid({
    required this.calibration,
    required List<SceneSpatialElement> cells,
  }) : cells = List.unmodifiable(cells) {
    final ids = <String>{};
    for (final cell in cells) {
      final index = MetricCellIndex.tryParse(cell.id);
      if (index == null || !calibration.contains(index)) {
        throw ArgumentError.value(
          cell.id,
          'cells',
          'Metric cell is outside the calibrated grid.',
        );
      }
      if (!ids.add(cell.id)) {
        throw ArgumentError.value(cell.id, 'cells', 'Duplicate metric cell.');
      }
    }
  }

  SceneSpatialElement? cellAt(MetricCellIndex index) {
    if (!calibration.contains(index)) return null;
    for (final cell in cells) {
      if (cell.id == index.elementId) return cell;
    }
    return null;
  }
}
