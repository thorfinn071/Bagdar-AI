import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/camera_track_association.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/planning/coverage_aware_stop_guidance.dart';
import 'package:bagdar/safety/runtime/confidence_authority_spatial_runtime.dart';
import 'package:bagdar/safety/runtime/passage_clearance_shadow.dart';
import 'package:bagdar/services/fall_detector.dart';
import 'package:bagdar/services/generic_obstacle_detector.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/depth_map_ops.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/blender_visible_body_fixture.dart';
import 'harness/camera_view_coverage_diagnostics.dart';
import 'harness/camera_visible_passage_fixture.dart' show copyVisibleFrame;

const _root = String.fromEnvironment(
  'BAGDAR_VIEW_TRIAL',
  defaultValue: 'scratch/camera-view-coverage-2026-10-09/optical',
);
const _write = bool.fromEnvironment('BAGDAR_WRITE_VIEW_REPORT');
const _check = bool.fromEnvironment('BAGDAR_CHECK_VIEW_REPORT');
const _experiment = bool.fromEnvironment('BAGDAR_VIEW_EXPERIMENT');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'frozen clear approach maps match whole-cell source for every frame',
    () {
      final fixture = PairedBodyFixture();
      final packets =
          ((fixture.manifest['sequences'] as List).cast<Map>().singleWhere(
                    (s) => s['sceneId'] == 'path-clear',
                  )['single']
                  as List)
              .cast<Map>();
      final rows = <Map<String, Object?>>[];
      for (final packet in packets) {
        final f = fixture.visible(packet, 'path-clear');
        final source = CameraPassageClearanceSource(
          calibration: fixture.calibration('path-clear'),
          request: pairedBodyRequest,
          frames: [f],
          producedAtUs: f.capturedAtUs + 1000,
        );
        final observation = source.observationFor(_context(f))!;
        final diagnostic = CameraViewCoverageDiagnostics(
          frame: f,
          request: pairedBodyRequest,
        ).inspect(source, observation);
        expect(diagnostic['replicaMatchesSource'], true);
        expect(source.unknownBodyBoxes, inInclusiveRange(460, 477));
        rows.add({'frameId': f.frameId, ...diagnostic});
      }
      _receipt('baseline-maps.json', {
        'promotionAllowed': false,
        'scope': 'frozen known 11-frame source; diagnostic only',
        'manifestSha256': fixture.modelHash,
        'frames': rows,
      });
    },
  );

  test(
    'new views use matching regenerated neural and synthetic optical inputs',
    () {
      final manifest = bodyJson('$_root/manifest.json');
      final neural = bodyJson('$_root/neural.json');
      expect(manifest['promotionAllowed'], false);
      expect(neural['promotionAllowed'], false);
      expect(neural['manifestSha256'], bodySha('$_root/manifest.json'));
      expect(manifest['packets'], hasLength(35));
      expect(neural['frames'], hasLength(35));
      for (final receipt in [manifest, neural]) {
        for (final e in (receipt['sources'] as Map).entries) {
          expect(bodySha(e.key as String), e.value, reason: e.key as String);
        }
      }
      expect(
        bodySha('assets/midas_small.ncnn.param'),
        neural['modelParamSha256'],
      );
      expect(bodySha('assets/midas_small.ncnn.bin'), neural['modelBinSha256']);
      final relativeHash =
          'param:${neural['modelParamSha256']};bin:${neural['modelBinSha256']}';
      final opticalHash = bodySha('$_root/manifest.json');
      final prior = PairedBodyFixture();
      final rows = <Map<String, Object?>>[];
      final faultRows = <Map<String, Object?>>[];
      final originalMatches = <Map<String, Object?>>[];
      for (final packet in (manifest['packets'] as List).cast<Map>()) {
        // Labels are used only after the observation/runtime have been evaluated.
        final caseId = packet['caseId'] as String,
            viewId = packet['viewId'] as String;
        final transform = 'view-$caseId-$viewId-256x256';
        final us = pairedBodyStamp + (packet['capturedOffsetMs'] as int) * 1000;
        final f = CameraVisibleDepthFrame(
          width: packet['width'] as int,
          height: packet['height'] as int,
          frameId: packet['frameId'] as int,
          capturedAtUs: us,
          sessionGeneration: 1,
          fx: (packet['fx'] as num).toDouble(),
          fy: (packet['fy'] as num).toDouble(),
          cx: (packet['cx'] as num).toDouble(),
          cy: (packet['cy'] as num).toDouble(),
          errorM: 0,
          poseQuality: 1,
          cameraId: 'view-single-camera',
          modelHash: opticalHash,
          transformId: transform,
          referenceFrameId: pairedBodyRequest.referenceFrameId,
          units: PassageUnits.metricMeters,
          providerHealthy: true,
          rotation: (packet['cameraToWalkingRotation'] as List)
              .map((x) => (x as num).toDouble())
              .toList(),
          originM: (packet['cameraOriginM'] as List)
              .map((x) => (x as num).toDouble())
              .toList(),
          rangeM: bodyFloats(bodyAsset(_root, packet['depth'] as Map)),
          freeZLowerM: bodyFloats(
            bodyAsset(_root, packet['freeZLower'] as Map),
          ),
          surfaceZUpperM: bodyFloats(
            bodyAsset(_root, packet['surfaceZUpper'] as Map),
          ),
          valid: gzip
              .decode(bodyAsset(_root, packet['validity'] as Map))
              .map((v) => v == 1)
              .toList(),
        );
        final calibration = PassageCalibration(
          id: 'view-synthetic-whole-pixel-v1',
          providerId: 'view-synthetic-metric',
          modelId: 'first-return-whole-pixel-v1',
          modelHash: opticalHash,
          preprocessId: 'opaque-first-return-whole-pixel-v1',
          referenceFrameId: pairedBodyRequest.referenceFrameId,
          transformId: transform,
          timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
          metricScaleValidated: true,
          alignmentValidated: true,
          floorReferenceValidated: true,
        );
        CameraPassageClearanceSource sourceFor(CameraVisibleDepthFrame input) =>
            CameraPassageClearanceSource(
              calibration: calibration,
              request: pairedBodyRequest,
              frames: [input],
              producedAtUs: us + 1000,
            );
        final source = sourceFor(f);
        final observation = source.observationFor(_context(f))!;
        final gate = const PassageClearanceEvaluator(policy: pairedBodyPolicy)
            .evaluate(
              request: pairedBodyRequest,
              context: _context(f),
              calibration: calibration,
              observation: observation,
            );
        final diagnostic = CameraViewCoverageDiagnostics(
          frame: f,
          request: pairedBodyRequest,
        ).inspect(source, observation);
        final record = (neural['frames'] as List).cast<Map>().singleWhere(
          (r) => r['caseId'] == caseId && r['viewId'] == viewId,
        );
        bodyAsset(_root, packet['rgb'] as Map);
        expect(record['rgbSha256'], (packet['rgb'] as Map)['sha256']);
        final raw = bodyFloats(bodyAsset(_root, record['asset'] as Map));
        expect(raw.length, 65536);
        expect(raw.every((v) => v.isFinite), true);
        final relative = DepthFrame(
          values: DepthMapOps.normalizeRelativeProximity(
            Float32List.fromList(raw),
          ),
          confidence01: Float32List.fromList(List.filled(raw.length, 1)),
          width: 256,
          height: 256,
          timestampUs: us,
          provider: DepthProviderKind.ncnnRelative,
          semantics: DepthValueSemantics.relativeProximity,
          modelId: 'midas-small-ncnn',
          modelHash: relativeHash,
          preprocessId: neural['preprocessId'] as String,
          cropTopFraction: 0,
          frameQuality: 1,
          alignedToImage: true,
        );
        final detection =
            GenericObstacleDetector(
              collectOpeningDiagnostics: true,
              collectCameraSupport: true,
            ).detect(
              frame: relative,
              pitchDeg: (packet['pitchDownDeg'] as num).toDouble(),
              rollDeg: 0,
              motion: MotionState.walking,
              imageTimestampUs: us,
            );
        final tracks = GenericObstacleTracker().update(
          observations: detection.observations,
          timestampUs: us,
          relative: true,
        );
        final header = ObservationHeader(
          providerId: 'desktop-midas',
          modelId: relative.modelId,
          modelHash: relative.modelHash,
          preprocessId: relative.preprocessId,
          sessionGeneration: 1,
          frameId: f.frameId,
          sourceTimestampUs: us,
          producedAtUs: us + 1000,
          transformId: transform,
          confidence: detection.detectorQuality.clamp(0, 1),
          health: ObservationHealth.healthy,
        );
        Map<String, Object?> runtimeRow(
          CameraVisibleDepthFrame input,
          PassageClearanceObservation? evidence, {
          int ageUs = 2000,
        }) {
          final runtime =
              ConfidenceAuthoritySpatialRuntime(
                healthCoordinator: CoreHealthCoordinator(),
                planner: CoverageAwareStopGuidance(),
                shadowPassage: PassageClearanceShadowConfiguration(
                  calibration: calibration,
                  request: pairedBodyRequest,
                  policy: pairedBodyPolicy,
                  requireCameraEvidence: true,
                  associateCameraTracks: true,
                  cameraTrackModelHash: relativeHash,
                ),
              )..beginSession(
                1,
                now: DateTime.fromMicrosecondsSinceEpoch(us - 1000),
              );
          final result = runtime.ingestGenericGeometry(
            header: header,
            detection: detection,
            tracks: tracks,
            now: DateTime.fromMicrosecondsSinceEpoch(us + ageUs),
            orientationValid: true,
            userMoving: true,
            poseQuality: 1,
            passageObservation: evidence,
            cameraTrackInput: CameraTrackAssociationInput(
              rgbHeader: header,
              depth: input,
              imageGeometry: CameraTrackImageGeometry(
                cameraId: input.cameraId,
                width: input.width,
                height: input.height,
                fx: input.fx,
                fy: input.fy,
                cx: input.cx,
                cy: input.cy,
                rotation: input.rotation,
                originM: input.originM,
              ),
            ),
          );
          expect(result.accepted, true, reason: '$caseId/$viewId/$ageUs');
          expect(result.submittedAction?.delivery.name, 'shadow');
          expect(runtime.arbiter.active, isNull);
          return {
            'action': result.decision!.action.kind.name,
            'rule': result.decision!.action.ruleId,
            'delivery': result.submittedAction!.delivery.name,
            'passageApplied': result.passageClearanceApplied,
            'passage': result.passageClearance?.toDiagnosticMap(),
            'associationReasons': [
              for (final a in runtime.cameraTrackAssociations.values) a.reason,
            ],
          };
        }

        final action = runtimeRow(f, observation);
        final hazard = packet['physicalHazard'] as bool;
        if (hazard) {
          expect(
            gate.status,
            isNot(PassageClearanceStatus.measuredClear),
            reason: '$caseId/$viewId',
          );
          expect(action['action'], 'stopNow', reason: '$caseId/$viewId');
          expect(action['passageApplied'], false);
        }
        rows.add({
          'caseId': caseId,
          'viewId': viewId,
          'physicalHazard': hazard,
          'heightM': f.originM[2],
          'pitchDownDeg': packet['pitchDownDeg'],
          'lensMm': packet['lensMm'],
          'sourcePassage': gate.toDiagnosticMap(),
          'runtime': action,
          'coverage': diagnostic,
          'rgbSha256': record['rgbSha256'],
          'neuralSha256': (record['asset'] as Map)['sha256'],
        });
        if (viewId == 'original' && packet['syntheticContrast'] == null) {
          final optics = (prior.manifest['sequences'] as List)
              .cast<Map>()
              .singleWhere((s) => s['sceneId'] == packet['sceneId']);
          final originalPacket =
              (optics['single'] as List)[packet['originalFrameIndex'] as int]
                  as Map;
          final oldFrame = prior.visible(
            originalPacket,
            packet['sceneId'] as String,
          );
          final oldSource = CameraPassageClearanceSource(
            calibration: prior.calibration(packet['sceneId'] as String),
            request: pairedBodyRequest,
            frames: [oldFrame],
            producedAtUs: us + 1000,
          );
          final oldObservation = oldSource.observationFor(_context(oldFrame))!;
          expect(source.certifiedBodyBoxes, oldSource.certifiedBodyBoxes);
          expect(source.unknownBodyBoxes, oldSource.unknownBodyBoxes);
          for (var i = 0; i < oldObservation.sections.length; i++) {
            expect(
              observation.sections[i].state,
              oldObservation.sections[i].state,
            );
            expect(
              observation.sections[i].bodyObservedFraction,
              oldObservation.sections[i].bodyObservedFraction,
            );
            expect(
              observation.sections[i].floorObservedFraction,
              oldObservation.sections[i].floorObservedFraction,
            );
          }
          var maxDelta = 0.0;
          for (var i = 0; i < f.rangeM.length; i++) {
            expect(f.valid[i], oldFrame.valid[i]);
            if (f.valid[i]) {
              final d = (f.rangeM[i] - oldFrame.rangeM[i]).abs();
              if (d > maxDelta) maxDelta = d;
            }
          }
          expect(maxDelta, lessThanOrEqualTo(2e-5));
          originalMatches.add({
            'caseId': caseId,
            'boxAndSectionParity': true,
            'maxRangeDeltaM': maxDelta,
          });
        }
        if (!hazard) {
          final holes = copyVisibleFrame(
            f,
            valid: List.filled(f.valid.length, false),
          );
          final relativeUnits = copyVisibleFrame(
            f,
            units: PassageUnits.relativeProximity,
          );
          for (final e in {
            'invalidPixels': holes,
            'relativeUnits': relativeUnits,
          }.entries) {
            final badObservation = sourceFor(
              e.value,
            ).observationFor(_context(f));
            final result = runtimeRow(e.value, badObservation);
            expect(
              result['action'],
              'stopNow',
              reason: '$caseId/$viewId/${e.key}',
            );
            expect(result['passageApplied'], false);
            expect((result['passage'] as Map)['status'], 'unavailable');
            faultRows.add({
              'caseId': caseId,
              'viewId': viewId,
              'fault': e.key,
              ...result,
            });
          }
          final stale = runtimeRow(f, observation, ageUs: 100001);
          expect(stale['action'], 'stopNow');
          expect(stale['passageApplied'], false);
          expect((stale['passage'] as Map)['status'], 'unavailable');
          faultRows.add({
            'caseId': caseId,
            'viewId': viewId,
            'fault': 'staleOriginalCapture',
            ...stale,
          });
        }
      }
      _receipt('comparison.json', {
        'schemaVersion': 1,
        'promotionAllowed': false,
        'ordinaryCameraWired': false,
        'falseStopReductionEstablished': false,
        'captureToCommandMeasured': false,
        'scope':
            '35 known synthetic current-view snapshots; new relative neural output plus renderer metric depth',
        'maximumAgeUs': pairedBodyPolicy.maximumAgeUs,
        'maximumFixedAgeUs': 2000,
        'manifestSha256': opticalHash,
        'neuralReceiptSha256': bodySha('$_root/neural.json'),
        'namedDeviceRuntime': 'not_run',
        'controlledWalking': 'not_run',
        'originalOpticalParity': originalMatches,
        'faultControls': faultRows,
        'frames': rows,
        'summary': [
          for (final view in [
            'original',
            'chest-level',
            'waist-level',
            'waist-down',
            'ideal-wide-control',
          ])
            {
              'viewId': view,
              'passableSnapshots': rows
                  .where(
                    (r) => r['viewId'] == view && r['physicalHazard'] == false,
                  )
                  .length,
              'passableStops': rows
                  .where(
                    (r) =>
                        r['viewId'] == view &&
                        r['physicalHazard'] == false &&
                        (r['runtime'] as Map)['action'] == 'stopNow',
                  )
                  .length,
              'passableMeasuredClear': rows
                  .where(
                    (r) =>
                        r['viewId'] == view &&
                        r['physicalHazard'] == false &&
                        (r['sourcePassage'] as Map)['status'] ==
                            'measuredClear',
                  )
                  .length,
              'hazardSnapshots': rows
                  .where(
                    (r) => r['viewId'] == view && r['physicalHazard'] == true,
                  )
                  .length,
              'hazardStops': rows
                  .where(
                    (r) =>
                        r['viewId'] == view &&
                        r['physicalHazard'] == true &&
                        (r['runtime'] as Map)['action'] == 'stopNow',
                  )
                  .length,
              'hazardUnsafeContinues': rows
                  .where(
                    (r) =>
                        r['viewId'] == view &&
                        r['physicalHazard'] == true &&
                        (r['runtime'] as Map)['action'] == 'continueForward',
                  )
                  .length,
            },
        ],
      });
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip: !_experiment,
  );
}

PassageEvaluationContext _context(CameraVisibleDepthFrame f) =>
    PassageEvaluationContext(
      nowUs: f.capturedAtUs + 2000,
      timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
      sessionGeneration: f.sessionGeneration,
      frameId: f.frameId,
      rgbTimestampUs: f.capturedAtUs,
      transformId: f.transformId,
    );

void _receipt(String name, Map<String, Object?> value) {
  final file = File('$_root/../$name');
  final rendered = '${const JsonEncoder.withIndent('  ').convert(value)}\n';
  if (_check) expect(file.readAsStringSync(), rendered);
  if (_write) {
    expect(file.existsSync(), false, reason: 'Trial receipt is write-once');
    file.writeAsStringSync(rendered);
  }
}
