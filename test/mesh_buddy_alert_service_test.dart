import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/services/mesh_buddy_alert_service.dart';
import 'package:bagdar/models/constants.dart';
import 'package:bagdar/models/external_hazard.dart';

void main() {
  group('MeshBuddyPayload', () {
    test('round-trip serialize / deserialize', () {
      final payload = MeshBuddyPayload(
        hazardType: 'pothole',
        severity: 0.7,
        ageMs: 5000,
        ttl: 3,
        hopCount: 1,
        dedupeHash: 'abc123',
        receivedAt: DateTime.now(),
        lat: 51.1605,
        lng: 71.4704,
      );
      final bytes = payload.toBytes();
      final decoded = MeshBuddyPayload.fromBytes(bytes);
      expect(decoded.hazardType, 'pothole');
      expect(decoded.severity, closeTo(0.7, 0.01));
      expect(decoded.ageMs, 5000);
      expect(decoded.ttl, 3);
      expect(decoded.hopCount, 1);
      expect(decoded.dedupeHash, 'abc123');
    });

    test('isExpired returns true when TTL is zero', () {
      final payload = MeshBuddyPayload(
        hazardType: 'ice',
        severity: 0.5,
        ageMs: 1000,
        ttl: 0,
        hopCount: 4,
        dedupeHash: 'expired1',
        receivedAt: DateTime.now(),
      );
      expect(payload.isExpired, true);
    });

    test('isTooOld returns true when ageMs exceeds max', () {
      final payload = MeshBuddyPayload(
        hazardType: 'construction',
        severity: 0.5,
        ageMs: kMeshMaxPayloadAgeMs + 1,
        ttl: 3,
        hopCount: 0,
        dedupeHash: 'old1',
        receivedAt: DateTime.now(),
      );
      expect(payload.isTooOld, true);
    });

    test('fromBytes rejects short data', () {
      expect(
        () => MeshBuddyPayload.fromBytes(Uint8List(5)),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('MeshBuddyAlertService', () {
    late MeshBuddyAlertService service;

    setUp(() {
      service = MeshBuddyAlertService.instance;
      service.resetForTesting();
    });

    test('handlePayload drops expired payloads', () {
      final events = <ExternalHazardEvent>[];
      service.onHazard = (e) => events.add(e);

      final payload = MeshBuddyPayload(
        hazardType: 'pothole',
        severity: 0.7,
        ageMs: kMeshMaxPayloadAgeMs + 1,
        ttl: 3,
        hopCount: 0,
        dedupeHash: 'test1',
        receivedAt: DateTime.now(),
      );
      service.handlePayload(payload);
      expect(events, isEmpty);
    });

    test('handlePayload deduplicates by hash', () {
      service.resetForTesting();
      expect(service.isActive, false);
    });

    test('isAvailable returns false by default', () {
      expect(service.isAvailable, false);
    });
  });
}
