import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/perception/single_camera_observability.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/blender_visible_body_fixture.dart';
import 'harness/replay_source_contract.dart';

const root = 'scratch/camera-view-coverage-2026-10-09/optical';
const outputRoot = 'scratch/single-camera-observability-2026-10-11';
const writeReport = bool.fromEnvironment('BAGDAR_WRITE_OBSERVABILITY');
const checkReport = bool.fromEnvironment('BAGDAR_CHECK_OBSERVABILITY');

void main() {
  test(
    'one view retains near gaps and partial evidence cannot replace full recovery',
    () {
      verifyReplaySourceContract(
        'test/fixtures/spatial_safety/scan-replay-source-contract-v1.json',
      );
      final manifest = bodyJson('$root/manifest.json');
      final old = bodyJson(
        'scratch/camera-view-coverage-2026-10-09/comparison.json',
      );
      final hash = bodySha('$root/manifest.json');
      expect(old['manifestSha256'], hash);
      for (final item in (manifest['sources'] as Map).entries) {
        expect(
          bodySha(item.key as String),
          item.value,
          reason: item.key as String,
        );
      }
      final rows = <Map<String, Object?>>[];
      for (final packet in (manifest['packets'] as List).cast<Map>()) {
        final transform =
            'view-${packet['caseId']}-${packet['viewId']}-256x256';
        final timestamp =
            pairedBodyStamp + (packet['capturedOffsetMs'] as int) * 1000;
        final frame = CameraVisibleDepthFrame(
          width: packet['width'] as int,
          height: packet['height'] as int,
          frameId: packet['frameId'] as int,
          capturedAtUs: timestamp,
          sessionGeneration: 1,
          fx: (packet['fx'] as num).toDouble(),
          fy: (packet['fy'] as num).toDouble(),
          cx: (packet['cx'] as num).toDouble(),
          cy: (packet['cy'] as num).toDouble(),
          errorM: 0,
          poseQuality: 1,
          cameraId: 'view-single-camera',
          modelHash: hash,
          transformId: transform,
          referenceFrameId: pairedBodyRequest.referenceFrameId,
          units: PassageUnits.metricMeters,
          providerHealthy: true,
          rotation: (packet['cameraToWalkingRotation'] as List)
              .map((v) => (v as num).toDouble())
              .toList(),
          originM: (packet['cameraOriginM'] as List)
              .map((v) => (v as num).toDouble())
              .toList(),
          rangeM: bodyFloats(bodyAsset(root, packet['depth'] as Map)),
          freeZLowerM: bodyFloats(bodyAsset(root, packet['freeZLower'] as Map)),
          surfaceZUpperM: bodyFloats(
            bodyAsset(root, packet['surfaceZUpper'] as Map),
          ),
          valid: gzip
              .decode(bodyAsset(root, packet['validity'] as Map))
              .map((v) => v == 1)
              .toList(),
        );
        final calibration = PassageCalibration(
          id: 'view-synthetic-whole-pixel-v1',
          providerId: 'view-synthetic-metric',
          modelId: 'first-return-whole-pixel-v1',
          modelHash: hash,
          preprocessId: 'opaque-first-return-whole-pixel-v1',
          referenceFrameId: pairedBodyRequest.referenceFrameId,
          transformId: transform,
          timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
          metricScaleValidated: true,
          alignmentValidated: true,
          floorReferenceValidated: true,
        );
        final context = PassageEvaluationContext(
          nowUs: timestamp + 2000,
          timestampDomain: calibration.timestampDomain,
          sessionGeneration: 1,
          frameId: frame.frameId,
          rgbTimestampUs: timestamp,
          transformId: transform,
        );
        final preflight = const SingleCameraObservabilityPreflight().assess(
          frame: frame,
          calibration: calibration,
          request: pairedBodyRequest,
          context: context,
        );
        expect(preflight.inputsAdmitted, true);
        expect(preflight.canAuthorizeMovement, false);
        PassageClearanceResult measure(PassageClearanceRequest request) =>
            const PassageClearanceEvaluator(policy: pairedBodyPolicy).evaluate(
              request: request,
              context: context,
              calibration: calibration,
              observation: CameraPassageClearanceSource(
                calibration: calibration,
                request: request,
                frames: [frame],
                producedAtUs: timestamp + 1000,
              ).observationFor(context),
            );
        final full = measure(pairedBodyRequest);
        // Previous outcomes remain exact; constructing a partial request must
        // never mutate the original provider/request or its stored denominator.
        final previous = (old['frames'] as List).cast<Map>().singleWhere(
          (r) =>
              r['caseId'] == packet['caseId'] &&
              r['viewId'] == packet['viewId'],
        );
        expect(full.toDiagnosticMap(), previous['sourcePassage']);

        Map<String, Object?>? partial;
        if (preflight.visibleStartM != null) {
          final start = ((preflight.visibleStartM! + .02) * 20).ceil() / 20;
          final end = math.min(
            pairedBodyRequest.forwardEndM,
            preflight.visibleEndM! - .02,
          );
          if (end - start >= .1) {
            final request = PassageClearanceRequest(
              referenceFrameId: pairedBodyRequest.referenceFrameId,
              lateralCenterM: pairedBodyRequest.lateralCenterM,
              widthM: pairedBodyRequest.widthM,
              headroomM: pairedBodyRequest.headroomM,
              forwardStartM: start,
              forwardEndM: end,
              maximumFloorRiseM: pairedBodyRequest.maximumFloorRiseM,
              maximumFloorDropM: pairedBodyRequest.maximumFloorDropM,
            );
            final result = measure(request);
            expect(result.coversCameraRecoveryVolume, false);
            expect(
              result.appliesTo(request: pairedBodyRequest, context: context),
              false,
            );
            partial = {
              'startM': start,
              'endM': end,
              ...result.toDiagnosticMap(),
              'coversCameraRecoveryVolume': result.coversCameraRecoveryVolume,
              'appliesToFullRequest': result.appliesTo(
                request: pairedBodyRequest,
                context: context,
              ),
            };
          }
        }
        // Labels used after all geometric and measurement outcomes are final.
        rows.add({
          'caseId': packet['caseId'],
          'viewId': packet['viewId'],
          'physicalHazard': packet['physicalHazard'],
          'geometry': preflight.toDiagnosticMap(),
          'full': full.toDiagnosticMap(),
          'partial': partial,
          'priorRuntimeAction': previous['runtime']['action'],
        });
      }
      expect(rows, hasLength(35));
      final report = {
        'schemaVersion': 1,
        'scope':
            'known synthetic view diagnostics; no new inference or runtime wiring',
        'sourceManifestSha256': hash,
        'priorReportSha256': bodySha(
          'scratch/camera-view-coverage-2026-10-09/comparison.json',
        ),
        'maximumAgeUs': 100000,
        'fixedReplayAgeUs': 2000,
        'promotionAllowed': false,
        'ordinaryCameraWired': false,
        'falseStopReductionEstablished': false,
        'latencyMeasured': false,
        'rows': rows,
      };
      final file = File('$outputRoot/experiment.json');
      final text = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
      if (writeReport) {
        expect(file.existsSync(), false);
        file.writeAsStringSync(text);
      }
      if (checkReport || !writeReport) {
        expect(file.readAsStringSync(), text);
      }
    },
  );
}
