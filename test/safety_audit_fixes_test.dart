import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/camera/depth_pipeline_controller.dart';
import 'package:bagdar/models/constants.dart';
import 'package:bagdar/models/speech_job.dart';
import 'package:bagdar/utils/alert_filter.dart';
import 'package:bagdar/utils/depth_hazard.dart';

void main() {
  group(
    'Safety audit 2.1: COCO class whitelist (lib/models/constants.dart)',
    () {
      test('whitelist contains every danger-critical class', () {
        const mustInclude = {
          'person',
          'bicycle',
          'car',
          'motorcycle',
          'bus',
          'truck',
          'traffic light',
          'stop sign',
        };
        for (final label in mustInclude) {
          expect(
            kAlertClassWhitelist.contains(label),
            isTrue,
            reason:
                'Whitelist must contain "$label" — losing it would silently '
                'silence a danger-critical alert path.',
          );
        }
      });

      test(
        'whitelist excludes COCO classes that produce absurd alerts on a '
        'street',
        () {
          
          
          
          const irrelevantCocoClasses = {
            'airplane',
            'boat',
            'train',
            'horse',
            'sheep',
            'cow',
            'elephant',
            'bear',
            'zebra',
            'giraffe',
            'frisbee',
            'skis',
            'snowboard',
            'sports ball',
            'kite',
            'baseball bat',
            'baseball glove',
            'skateboard',
            'surfboard',
            'tennis racket',
            'wine glass',
            'cup',
            'fork',
            'knife',
            'spoon',
            'bowl',
            'banana',
            'apple',
            'sandwich',
            'orange',
            'broccoli',
            'carrot',
            'hot dog',
            'pizza',
            'donut',
            'cake',
            'couch',
            'bed',
            'dining table',
            'toilet',
            'tv',
            'laptop',
            'mouse',
            'remote',
            'keyboard',
            'cell phone',
            'microwave',
            'oven',
            'toaster',
            'sink',
            'refrigerator',
            'book',
            'clock',
            'vase',
            'scissors',
            'teddy bear',
            'hair drier',
            'toothbrush',
            'tie',
            'bird',
          };
          for (final label in irrelevantCocoClasses) {
            expect(
              kAlertClassWhitelist.contains(label),
              isFalse,
              reason:
                  'Whitelist must NOT contain "$label" — alerting on it '
                  'would erode user trust ("ahead: 3 sports ball") and '
                  'mask real warnings under spam.',
            );
          }
        },
      );

      test('whitelist contains exactly the audited 20 entries', () {
        
        
        expect(kAlertClassWhitelist, hasLength(20));
      });
    },
  );

  group(
    'Safety audit 2.2: per-class minimum confidence (kClassMinConf, '
    'minConfFor)',
    () {
      test(
        'pedestrians and vehicles have a 0.40 floor — high enough to gate '
        'noise, low enough to catch them at distance',
        () {
          for (final label in const {
            'person',
            'car',
            'bus',
            'truck',
            'motorcycle',
          }) {
            expect(
              minConfFor(label),
              closeTo(0.40, 1e-9),
              reason:
                  'danger-critical class "$label" must use the 0.40 '
                  'floor; raising it would lose distant pedestrians/'
                  'vehicles which is the dominant safety risk',
            );
          }
        },
      );

      test(
        'fixed indoor/carry hazards have a higher floor than people and '
        'vehicles (false positives more costly than missed detection)',
        () {
          expect(
            minConfFor('bottle'),
            greaterThan(minConfFor('person')),
          );
          expect(
            minConfFor('handbag'),
            greaterThan(minConfFor('person')),
          );
          expect(
            minConfFor('potted plant'),
            greaterThan(minConfFor('person')),
          );
        },
      );

      test(
        'unknown / non-whitelisted labels fall back to a conservative '
        'default — never below 0.40',
        () {
          expect(minConfFor('unknown'), kDefaultClassMinConf);
          expect(kDefaultClassMinConf, greaterThanOrEqualTo(0.40));
        },
      );
    },
  );

  group(
    'Safety audit 1.4: AlertFilter per-category critical suppression',
    () {
      test(
        'a critical in one category does NOT suppress a different critical '
        'category 1 second later',
        () {
          final f = AlertFilter();
          final t0 = DateTime(2025, 1, 1, 12);

          
          f.add(const AlertCandidate(
            text: 'Stop! corridor blocked',
            priority: SpeechPriority.critical,
            pan: 0.0,
            category: AlertCategory.corridorBlocked,
            urgency: 0.9,
          ));
          final first = f.flush(0, t0);
          expect(first, isNotNull);
          expect(first!.category, AlertCategory.corridorBlocked);

          
          
          
          
          
          f.add(const AlertCandidate(
            text: 'Stop! pothole ahead',
            priority: SpeechPriority.critical,
            pan: 0.0,
            category: AlertCategory.obstacleClose,
            urgency: 0.9,
          ));
          final second = f.flush(
            0,
            t0.add(const Duration(seconds: 1)),
          );
          expect(
            second,
            isNotNull,
            reason:
                'Safety audit 1.4: corridorBlocked critical must not '
                'suppress an obstacleClose critical from a different '
                'category — they describe different hazards and the '
                'user must hear both.',
          );
          expect(second!.category, AlertCategory.obstacleClose);
        },
      );

      test(
        'a critical DOES still suppress a same-category warning for ~2 s '
        '(per-category suppression, not blanket)',
        () {
          final f = AlertFilter();
          final t0 = DateTime(2025, 1, 1, 12);

          f.add(const AlertCandidate(
            text: 'Stop! pothole',
            priority: SpeechPriority.critical,
            pan: 0.0,
            category: AlertCategory.obstacleClose,
            urgency: 0.9,
          ));
          expect(f.flush(0, t0), isNotNull);

          f.add(const AlertCandidate(
            text: 'pothole close',
            priority: SpeechPriority.warning,
            pan: 0.0,
            category: AlertCategory.obstacleClose,
            urgency: 0.5,
          ));
          final follow = f.flush(0, t0.add(const Duration(milliseconds: 500)));
          expect(
            follow,
            isNull,
            reason:
                'a warning in the SAME category as a recent critical '
                'must still be suppressed for the 2-s post-critical '
                'window — only cross-category criticals/warnings are '
                'unblocked.',
          );
        },
      );
    },
  );

  group(
    'Safety audit 3.1: depth-hazard critical promotion '
    '(DepthPipelineController.isHazardCriticalForTesting)',
    () {
      DepthHazard make(
        DepthHazardType type, {
        double score = 0.70,
        HazardZone zone = HazardZone.center,
      }) =>
          DepthHazard(
            midasScore: score,
            type: type,
            zone: zone,
            coverage: 0.5,
          );

      test('stairsDown stays critical (existing behaviour preserved)', () {
        expect(
          DepthPipelineController.isHazardCriticalForTesting(
            make(DepthHazardType.stairsDown),
            rollExcessive: false,
          ),
          isTrue,
        );
      });

      test('overhead stays critical', () {
        expect(
          DepthPipelineController.isHazardCriticalForTesting(
            make(DepthHazardType.overhead),
            rollExcessive: false,
          ),
          isTrue,
        );
      });

      test(
        'pothole in the centre zone with high score is critical (was a '
        'warning before — Safety audit 3.1)',
        () {
          expect(
            DepthPipelineController.isHazardCriticalForTesting(
              make(DepthHazardType.pothole, score: 0.80),
              rollExcessive: false,
            ),
            isTrue,
            reason:
                'a center-zone pothole with score 0.80 is a trip hazard '
                'and must compete in the critical lane, not lose to a '
                'queued info utterance under contention.',
          );
        },
      );

      test(
        'pothole at the periphery (left/right zone) stays a warning even '
        'at high score — only the user\'s walking corridor is critical',
        () {
          expect(
            DepthPipelineController.isHazardCriticalForTesting(
              make(
                DepthHazardType.pothole,
                score: 0.80,
                zone: HazardZone.left,
              ),
              rollExcessive: false,
            ),
            isFalse,
          );
          expect(
            DepthPipelineController.isHazardCriticalForTesting(
              make(
                DepthHazardType.pothole,
                score: 0.80,
                zone: HazardZone.right,
              ),
              rollExcessive: false,
            ),
            isFalse,
          );
        },
      );

      test('stepDown center-zone with high score is critical (3.1)', () {
        expect(
          DepthPipelineController.isHazardCriticalForTesting(
            make(DepthHazardType.stepDown, score: 0.80),
            rollExcessive: false,
          ),
          isTrue,
        );
      });

      test('glassDoor center-zone with high score is critical (3.1)', () {
        expect(
          DepthPipelineController.isHazardCriticalForTesting(
            make(DepthHazardType.glassDoor, score: 0.75),
            rollExcessive: false,
          ),
          isTrue,
          reason:
              'a glass door directly ahead is a head-strike hazard; '
              'losing it under alert contention would let the user walk '
              'face-first into glass.',
        );
      });

      test(
        'nearFieldIntrusion is critical regardless of zone whenever the '
        'score is high (object materialised at foot range)',
        () {
          for (final zone in HazardZone.values) {
            expect(
              DepthPipelineController.isHazardCriticalForTesting(
                make(
                  DepthHazardType.nearFieldIntrusion,
                  score: 0.65,
                  zone: zone,
                ),
                rollExcessive: false,
              ),
              isTrue,
              reason:
                  'a near-field intrusion at zone=$zone with score 0.65 '
                  'must be critical — it represents an object that '
                  'materialised within 0.5–1 m of the user.',
            );
          }
        },
      );

      test(
        'low-score hazards (just above the warning floor) stay as '
        'warnings, not critical',
        () {
          
          
          expect(
            DepthPipelineController.isHazardCriticalForTesting(
              make(DepthHazardType.pothole, score: 0.50),
              rollExcessive: false,
            ),
            isFalse,
          );
          expect(
            DepthPipelineController.isHazardCriticalForTesting(
              make(DepthHazardType.glassDoor, score: 0.50),
              rollExcessive: false,
            ),
            isFalse,
          );
        },
      );

      test(
        'rollExcessive (phone tilted sideways) demotes everything to '
        'warning to avoid spurious criticals from a misoriented depth map',
        () {
          for (final type in const [
            DepthHazardType.stairsDown,
            DepthHazardType.overhead,
            DepthHazardType.pothole,
            DepthHazardType.glassDoor,
            DepthHazardType.nearFieldIntrusion,
          ]) {
            expect(
              DepthPipelineController.isHazardCriticalForTesting(
                make(type, score: 0.85),
                rollExcessive: true,
              ),
              isFalse,
              reason:
                  'with the phone rolled sideways, depth interpretation '
                  'is unreliable so even high-score $type must not fire '
                  'a critical-priority alert.',
            );
          }
        },
      );

      test(
        'curb / lowCurb / stepUp / slippery / deadZone never become '
        'critical via this path (they remain warnings)',
        () {
          for (final type in const [
            DepthHazardType.curb,
            DepthHazardType.lowCurb,
            DepthHazardType.stepUp,
            DepthHazardType.slippery,
            DepthHazardType.deadZone,
          ]) {
            expect(
              DepthPipelineController.isHazardCriticalForTesting(
                make(type, score: 0.95),
                rollExcessive: false,
              ),
              isFalse,
              reason:
                  '$type is a heads-up advisory, not a stop-now alert; '
                  'promoting it to critical would mask actual stop-now '
                  'hazards under cooldown.',
            );
          }
        },
      );
    },
  );
}
