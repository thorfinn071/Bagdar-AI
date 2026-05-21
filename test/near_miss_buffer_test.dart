import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/models/constants.dart';
import 'package:bagdar/services/near_miss_buffer.dart';

void main() {
  group('NearMissRecord', () {
    test('round-trip JSON serialization', () {
      final record = NearMissRecord(
        id: 'nm_test1',
        at: DateTime(2026, 5, 15, 10, 0, 0),
        triggerSource: 'voice',
        labels: ['car', 'person'],
        closestDistM: 1.5,
        hazardType: 'pothole',
        depthScore: 0.85,
        acousticClass: 'horn',
        lat: 51.1605,
        lng: 71.4704,
        userNote: 'dangerous crossing',
      );
      final json = record.toJson();
      final decoded = NearMissRecord.fromJson(json);

      expect(decoded.id, 'nm_test1');
      expect(decoded.triggerSource, 'voice');
      expect(decoded.labels, ['car', 'person']);
      expect(decoded.closestDistM, 1.5);
      expect(decoded.hazardType, 'pothole');
      expect(decoded.depthScore, 0.85);
      expect(decoded.acousticClass, 'horn');
      expect(decoded.lat, 51.1605);
      expect(decoded.lng, 71.4704);
      expect(decoded.userNote, 'dangerous crossing');
    });

    test('optional fields can be null', () {
      final record = NearMissRecord(
        id: 'nm_test2',
        at: DateTime.now(),
        triggerSource: 'button',
        labels: const [],
      );
      final json = record.toJson();
      expect(json.containsKey('distM'), false);
      expect(json.containsKey('hazType'), false);
      expect(json.containsKey('lat'), false);
    });
  });

  group('NearMissBuffer', () {
    test('kNearMissMaxRecords is 100', () {
      expect(kNearMissMaxRecords, 100);
    });
  });
}
