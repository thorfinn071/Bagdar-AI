import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/camera/depth_pipeline_controller.dart';
import 'package:bagdar/models/constants.dart';
import 'package:bagdar/models/speech_job.dart';
import 'package:bagdar/services/motion_prealert.dart';
import 'package:bagdar/tracker/raw_det.dart';
import 'package:bagdar/tracker/tracker.dart';
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
        'rollExcessive does NOT demote hazards whose detection is '
        'independent of plane geometry (Safety follow-up H5)',
        () {
          for (final type in const [
            DepthHazardType.stairsDown,
            DepthHazardType.overhead,
            DepthHazardType.glassDoor,
            DepthHazardType.nearFieldIntrusion,
          ]) {
            expect(
              DepthPipelineController.isHazardCriticalForTesting(
                make(type, score: 0.85),
                rollExcessive: true,
              ),
              isTrue,
              reason:
                  '$type is a flat-against-user / luma-based hazard whose '
                  'detection does not rely on plane fit; rolling the phone '
                  'must not strip the critical tier from a head-strike or '
                  'fall-cliff alert.',
            );
          }
        },
      );

      test(
        'rollExcessive DOES demote hazards that depend on plane geometry '
        '(pothole, stepDown — Safety follow-up H5)',
        () {
          for (final type in const [
            DepthHazardType.pothole,
            DepthHazardType.stepDown,
          ]) {
            expect(
              DepthPipelineController.isHazardCriticalForTesting(
                make(type, score: 0.85),
                rollExcessive: true,
              ),
              isFalse,
              reason:
                  '$type is RANSAC-plane-derived; with the phone rolled '
                  'sideways the plane fit is unreliable so a high-score '
                  '$type must drop to warning to avoid spurious criticals.',
            );
          }
        },
      );

      test(
        'curb / lowCurb / stepUp / deadZone never become critical via this '
        'path (they remain warnings)',
        () {
          for (final type in const [
            DepthHazardType.curb,
            DepthHazardType.lowCurb,
            DepthHazardType.stepUp,
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

      test(
        'slippery in the centre walking corridor while moving is critical',
        () {
          expect(
            DepthPipelineController.isHazardCriticalForTesting(
              make(DepthHazardType.slippery, score: 0.55),
              rollExcessive: false,
              userStationary: false,
            ),
            isTrue,
            reason: 'black ice ahead while the user is walking is the leading '
                'cause of pedestrian injury in northern climates and must '
                'barge-in, not queue behind info chatter.',
          );
        },
      );

      test(
        'slippery off-corridor stays warning even at high score',
        () {
          for (final zone in const [HazardZone.left, HazardZone.right]) {
            expect(
              DepthPipelineController.isHazardCriticalForTesting(
                make(DepthHazardType.slippery, score: 0.90, zone: zone),
                rollExcessive: false,
                userStationary: false,
              ),
              isFalse,
              reason: 'slippery away from the walking corridor is not a '
                  'stop-now hazard',
            );
          }
        },
      );

      test(
        'slippery while user is stationary stays warning regardless of score',
        () {
          expect(
            DepthPipelineController.isHazardCriticalForTesting(
              make(DepthHazardType.slippery, score: 0.95),
              rollExcessive: false,
              userStationary: true,
            ),
            isFalse,
            reason: 'a stationary user is not about to slip on the patch '
                'they can already see in front of them',
          );
        },
      );

      test(
        'slippery below the score floor stays warning',
        () {
          expect(
            DepthPipelineController.isHazardCriticalForTesting(
              make(DepthHazardType.slippery, score: 0.49),
              rollExcessive: false,
              userStationary: false,
            ),
            isFalse,
          );
        },
      );
    },
  );

  group(
    'Safety audit 2.5: preserve approaching across short predict-only '
    'gaps (lib/tracker/tracker.dart)',
    () {
      RawDet det({
        required String label,
        required double x1,
        required double y1,
        required double x2,
        required double y2,
        double conf = 0.75,
      }) {
        return RawDet(
          label: label,
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
          cx: (x1 + x2) / 2.0,
          cy: (y1 + y2) / 2.0,
          conf: conf,
          dist: 'far',
          distM: 0.0,
        );
      }

      
      
      
      
      
      void confirmApproaching(Tracker tr, DateTime base) {
        tr.update(
          [det(label: 'car', x1: 200, y1: 200, x2: 260, y2: 260)],
          640,
          480,
          base,
        );
        tr.update(
          [det(label: 'car', x1: 195, y1: 193, x2: 280, y2: 285)],
          640,
          480,
          base.add(const Duration(milliseconds: 200)),
        );
        final out = tr.update(
          [det(label: 'car', x1: 190, y1: 185, x2: 330, y2: 330)],
          640,
          480,
          base.add(const Duration(milliseconds: 700)),
        );
        expect(out, hasLength(1));
        expect(
          out.single.approaching,
          isTrue,
          reason: 'pre-condition: vehicle approach must fire to set up '
              'the test',
        );
      }

      test(
        'a 2-frame predict-only burst (e.g. brief blur) does NOT erase the '
        'approaching flag on re-match — was the dominant false-negative '
        'in audit 2.5',
        () {
          final tr = Tracker();
          final base = DateTime(2025, 1, 1, 12);
          confirmApproaching(tr, base);

          
          
          tr.predict();
          tr.predict();

          
          
          final after = tr.update(
            [det(label: 'car', x1: 188, y1: 183, x2: 332, y2: 332)],
            640,
            480,
            base.add(const Duration(milliseconds: 900)),
          );
          expect(after, hasLength(1));
          expect(
            after.single.approaching,
            isTrue,
            reason: 'audit 2.5: short predict-only gaps must preserve '
                'approaching so the alert manager keeps treating the car '
                'as a threat after blur clears.',
          );
        },
      );

      test(
        'beyond the 3-frame preservation window predict-only clears '
        'approaching to avoid stale alerts on a drifted predicted box',
        () {
          final tr = Tracker();
          final base = DateTime(2025, 1, 1, 12);
          confirmApproaching(tr, base);

          
          
          List predicted = const [];
          for (int i = 0; i < 5; i++) {
            predicted = tr.predict();
          }

          expect(predicted, hasLength(1));
          expect(
            (predicted.single as dynamic).approaching,
            isFalse,
            reason: 'audit 2.5: after 4+ predict-only frames the kalman '
                'box has drifted enough that the prior approaching flag '
                'is untrustworthy; clear it to avoid stale alerts.',
          );
        },
      );
    },
  );

  group(
    'Safety audit 2.6: fast-track requires 2 frames OR audio '
    'corroboration (lib/tracker/tracker.dart)',
    () {
      RawDet vehicleAhead({double conf = 0.75}) => RawDet(
            label: 'person',
            x1: 100,
            y1: 100,
            x2: 200,
            y2: 380,
            cx: 150,
            cy: 240,
            conf: conf,
            dist: 'very close',
            distM: 0.9,
          );

      test(
        'a single-frame near very-close detection at 0.75 conf is '
        'suppressed without an audio corroboration — was firing a '
        'critical on 1 frame before audit 2.6',
        () {
          final tr = Tracker();
          final out = tr.update(
            [vehicleAhead()],
            640,
            480,
            DateTime(2025, 1, 1, 12),
          );
          expect(
            out,
            isEmpty,
            reason: 'audit 2.6: vision-only single-frame critical is too '
                'unreliable; require 2 confirmed frames or audio.',
          );
        },
      );

      test(
        'a single-frame detection at conf 0.75 fires when the acoustic '
        'model has emitted vehicleApproaching within the last 1 s',
        () {
          final now = DateTime(2025, 1, 1, 12);
          final tr = Tracker()
            ..lastVehicleApproachingAcousticAt =
                now.subtract(const Duration(milliseconds: 800));
          final out = tr.update([vehicleAhead()], 640, 480, now);
          expect(out, hasLength(1));
          expect(out.single.fastTrack, isTrue);
        },
      );

      test(
        'an acoustic event older than 1 s does NOT corroborate (window '
        'is short on purpose — stale audio is not a valid signal)',
        () {
          final now = DateTime(2025, 1, 1, 12);
          final tr = Tracker()
            ..lastVehicleApproachingAcousticAt =
                now.subtract(const Duration(milliseconds: 1500));
          final out = tr.update([vehicleAhead()], 640, 480, now);
          expect(out, isEmpty);
        },
      );

      test(
        'corroboration alone does not bypass the conf 0.75 floor — a '
        'lower-conf vision detection still needs 2-frame confirmation',
        () {
          final now = DateTime(2025, 1, 1, 12);
          final tr = Tracker()
            ..lastVehicleApproachingAcousticAt =
                now.subtract(const Duration(milliseconds: 200));
          final out = tr.update(
            [vehicleAhead(conf: 0.65)],
            640,
            480,
            now,
          );
          expect(
            out,
            isEmpty,
            reason: 'audit 2.6: the audio corroboration path requires '
                'conf >= 0.75 — at 0.65 we still wait for a 2nd frame.',
          );
        },
      );
    },
  );

  group(
    'Safety audit 5.3: motion pre-alert skips frames during AE '
    'transitions (lib/services/motion_prealert.dart)',
    () {
      Uint8List uniform(int v) {
        const n = kEventGridW * kEventGridH;
        return Uint8List(n)..fillRange(0, n, v);
      }

      test(
        'aeTransitioning=true returns null without processing — '
        'sun→shade auto-exposure flips no longer leak as motion events',
        () {
          final pa = MotionPreAlert();
          final t0 = DateTime(2025, 1, 1, 12);

          
          pa.feedDownsampledGrid(uniform(50), t0);

          
          
          final ev = pa.feedDownsampledGrid(
            uniform(200),
            t0.add(const Duration(milliseconds: 20)),
            aeTransitioning: true,
          );
          expect(
            ev,
            isNull,
            reason: 'audit 5.3: AE-transition frames must be skipped — '
                'a luma jump from sun→shade is the camera adjusting '
                'exposure, not a real motion event.',
          );
        },
      );

      test(
        'after an AE-transition skip, the next non-AE frame compares '
        'against the pre-AE baseline so no spurious event leaks out',
        () {
          final pa = MotionPreAlert();
          final t0 = DateTime(2025, 1, 1, 12);

          
          pa.feedDownsampledGrid(uniform(50), t0);

          
          pa.feedDownsampledGrid(
            uniform(200),
            t0.add(const Duration(milliseconds: 20)),
            aeTransitioning: true,
          );

          
          final ev = pa.feedDownsampledGrid(
            uniform(50),
            t0.add(const Duration(milliseconds: 40)),
          );
          expect(
            ev,
            isNull,
            reason: 'a stable post-AE frame relative to the pre-AE '
                'baseline must not emit a phantom motion event.',
          );
        },
      );
    },
  );
}
