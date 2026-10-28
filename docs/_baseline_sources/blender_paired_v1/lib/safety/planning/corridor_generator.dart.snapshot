import 'corridor_candidate.dart';
import 'corridor_evaluator.dart';
import '../world/relative_polar_grid.dart';

class CorridorGenerator {
  final CorridorEvaluator evaluator;

  const CorridorGenerator({this.evaluator = const CorridorEvaluator()});

  List<CorridorCandidate> generate(
    RelativePolarGrid grid, {
    required DateTime now,
    CorridorDirection? incumbentDirection,
  }) => CorridorDirection.values
      .map(
        (direction) => evaluator.evaluate(
          grid: grid,
          direction: direction,
          now: now,
          incumbentDirection: incumbentDirection,
        ),
      )
      .toList(growable: false);
}
