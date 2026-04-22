import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/services/weather_gate.dart';
import 'package:bagdar/utils/depth_hazard.dart';
import 'package:bagdar/utils/ground_plane_analyzer.dart';






void main() {
  group('WeatherGate state machine', () {
    test('starts in a non-degraded state and stays there on clear frames', () {
      final gate = WeatherGate();
      expect(gate.degraded, isFalse);
      for (int i = 0; i < 20; i++) {
        final t = gate.feed(800.0, 120.0);
        expect(t, WeatherTransition.none);
      }
      expect(gate.degraded, isFalse);
    });

    test(
      'fires degraded exactly on the tenth consecutive low-vis frame',
      () {
        final gate = WeatherGate();
        
        for (int i = 0; i < 9; i++) {
          final t = gate.feed(100.0, 200.0);
          expect(t, WeatherTransition.none);
          expect(gate.degraded, isFalse);
        }
        final trip = gate.feed(100.0, 200.0);
        expect(trip, WeatherTransition.degraded);
        expect(gate.degraded, isTrue);

        
        
        final after = gate.feed(100.0, 200.0);
        expect(after, WeatherTransition.none);
        expect(gate.degraded, isTrue);
      },
    );

    test('dark low-variance frames never qualify (camera-in-pocket case)', () {
      final gate = WeatherGate();
      for (int i = 0; i < 50; i++) {
        
        
        expect(gate.feed(100.0, 40.0), WeatherTransition.none);
      }
      expect(gate.degraded, isFalse);
    });

    test(
      'bright borderline variance (inside hysteresis gap) neither enters '
      'nor leaves the degraded state',
      () {
        final gate = WeatherGate();

        
        for (int i = 0; i < 10; i++) {
          gate.feed(100.0, 200.0);
        }
        expect(gate.degraded, isTrue);

        
        
        for (int i = 0; i < 100; i++) {
          expect(gate.feed(300.0, 200.0), WeatherTransition.none);
          expect(gate.degraded, isTrue);
        }
      },
    );

    test(
      'recovery requires thirty consecutive clearly-high-variance frames',
      () {
        final gate = WeatherGate();

        
        for (int i = 0; i < 10; i++) {
          gate.feed(100.0, 200.0);
        }
        expect(gate.degraded, isTrue);

        
        for (int i = 0; i < 29; i++) {
          expect(gate.feed(500.0, 120.0), WeatherTransition.none);
          expect(gate.degraded, isTrue);
        }
        final clear = gate.feed(500.0, 120.0);
        expect(clear, WeatherTransition.recovered);
        expect(gate.degraded, isFalse);
      },
    );

    test(
      'mixed low + high frames never enter or exit — streaks require '
      'strictly consecutive qualifying frames',
      () {
        final gate = WeatherGate();
        
        
        for (int i = 0; i < 200; i++) {
          final t = (i.isEven)
              ? gate.feed(100.0, 200.0)
              : gate.feed(500.0, 120.0);
          expect(t, WeatherTransition.none);
        }
        expect(gate.degraded, isFalse);
      },
    );

    test(
      'reset() drops all accumulated state so a partial streak does not '
      'carry over into the next session',
      () {
        final gate = WeatherGate();
        
        for (int i = 0; i < 9; i++) {
          gate.feed(100.0, 200.0);
        }
        gate.reset();
        expect(gate.degraded, isFalse);

        
        
        expect(gate.feed(100.0, 200.0), WeatherTransition.none);
        expect(gate.degraded, isFalse);
      },
    );

    test(
      'variance EXACTLY at the low threshold does not qualify — strict '
      '< comparison prevents boundary flaps',
      () {
        final gate = WeatherGate();
        for (int i = 0; i < 30; i++) {
          expect(gate.feed(200.0, 200.0), WeatherTransition.none);
        }
        expect(gate.degraded, isFalse);
      },
    );

    test(
      'recovery streak resets if a single low-vis frame slips back in',
      () {
        final gate = WeatherGate();
        
        for (int i = 0; i < 10; i++) {
          gate.feed(100.0, 200.0);
        }
        expect(gate.degraded, isTrue);

        
        for (int i = 0; i < 20; i++) {
          gate.feed(500.0, 120.0);
        }
        
        gate.feed(100.0, 200.0);

        
        for (int i = 0; i < 29; i++) {
          expect(gate.feed(500.0, 120.0), WeatherTransition.none);
        }
        expect(gate.degraded, isTrue);

        
        expect(gate.feed(500.0, 120.0), WeatherTransition.recovered);
        expect(gate.degraded, isFalse);
      },
    );
  });

  group('GroundPlaneAnalyzer weatherDegraded gating', () {
    const size = GroundPlaneAnalyzer.kMapSize;

    
    
    Float32List makeStaircaseMap() {
      final map = Float32List(size * size);
      for (int y = 0; y < size; y++) {
        final treadIndex = (y / 20).floor();
        final z = 0.4 + treadIndex * 0.08;
        for (int x = 0; x < size; x++) {
          map[y * size + x] = z;
        }
      }
      return map;
    }

    test(
      'stairs hazard is produced when weatherDegraded=false but suppressed '
      'when weatherDegraded=true',
      () {
        final analyzer = GroundPlaneAnalyzer();
        final map = makeStaircaseMap();

        
        final clear = analyzer.debugDetectStairsDown(
          map,
          userStationary: false,
        );
        expect(clear, isNotNull);
        expect(clear!.type, DepthHazardType.stairsDown);

        
        
        
        analyzer.resetTemporalFilter();
        final hazards = analyzer.analyze(
          map,
          weatherDegraded: true,
        );
        final stairsHit = hazards.any(
          (h) => h.type == DepthHazardType.stairsDown,
        );
        expect(stairsHit, isFalse);
      },
    );

    test(
      'weather flag does not stick across analyze calls — clear-weather '
      'invocation after a white-out still emits stairs',
      () {
        final analyzer = GroundPlaneAnalyzer();
        final map = makeStaircaseMap();

        
        analyzer.analyze(map, weatherDegraded: true);
        
        
        
        final recovered = analyzer.debugDetectStairsDown(
          map,
          userStationary: false,
        );
        expect(recovered, isNotNull);
        expect(recovered!.type, DepthHazardType.stairsDown);
      },
    );

    test(
      'near-field intrusion detection is NOT gated by weatherDegraded — '
      'delta-vs-baseline is robust under white-out',
      () {
        final analyzer = GroundPlaneAnalyzer();
        const bottomStart = GroundPlaneAnalyzer.kFootZoneStartRow;

        Float32List scene({required double bottomZ}) {
          final map = Float32List(size * size);
          for (int y = 0; y < size; y++) {
            final z = y >= bottomStart ? bottomZ : 0.30;
            for (int x = 0; x < size; x++) {
              map[y * size + x] = z;
            }
          }
          return map;
        }

        
        final calm = scene(bottomZ: 0.40);
        for (int i = 0; i < 6; i++) {
          analyzer.debugDetectNearFieldIntrusion(calm, userStationary: false);
        }

        
        
        
        
        final intrusion = scene(bottomZ: 0.70);
        analyzer.analyze(intrusion, weatherDegraded: true);
        final second = analyzer.debugDetectNearFieldIntrusion(
          intrusion,
          userStationary: false,
        );
        expect(second, isNotNull);
        expect(second!.type, DepthHazardType.nearFieldIntrusion);
      },
    );
  });
}
