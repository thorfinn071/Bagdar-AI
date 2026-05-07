import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/services/tts_service.dart';
import 'package:bagdar/models/speech_job.dart';










void main() {
  group('TtsService queue — OPT-07 critical preservation', () {
    test('two distinct critical alerts coexist in the queue', () {
      final svc = TtsService.forTesting();
      svc.say('stop, car left', SpeechPriority.critical);
      svc.say('stop, cyclist right', SpeechPriority.critical);

      expect(svc.queueSnapshot, hasLength(2));
      expect(
        svc.queueSnapshot.every((j) => j.priority == SpeechPriority.critical),
        isTrue,
      );
      expect(
        svc.queueSnapshot.map((j) => j.text).toSet(),
        {'stop, car left', 'stop, cyclist right'},
      );
    });

    test('critical drops pending warning and info jobs', () {
      final svc = TtsService.forTesting();
      svc.say('heads up', SpeechPriority.warning);
      svc.say('nav hint', SpeechPriority.info);
      expect(svc.queueSnapshot, hasLength(2));

      svc.say('stop, obstacle ahead', SpeechPriority.critical);

      expect(svc.queueSnapshot, hasLength(1));
      expect(svc.queueSnapshot.single.priority, SpeechPriority.critical);
      expect(svc.queueSnapshot.single.text, 'stop, obstacle ahead');
    });

    test('duplicate critical text does not inflate the queue', () {
      final svc = TtsService.forTesting();
      svc.say('stop, car left', SpeechPriority.critical);
      svc.say('stop, car left', SpeechPriority.critical);
      svc.say('stop, car left', SpeechPriority.critical);

      expect(svc.queueSnapshot, hasLength(1));
      expect(svc.queueSnapshot.single.text, 'stop, car left');
    });

    test(
        'critical preserves older critical even when warnings arrive between '
        'them', () {
      final svc = TtsService.forTesting();
      svc.say('stop, car left', SpeechPriority.critical);
      svc.say('slippery surface', SpeechPriority.warning);
      svc.say('stop, cyclist right', SpeechPriority.critical);

      final texts = svc.queueSnapshot.map((j) => j.text).toSet();
      expect(texts, contains('stop, car left'));
      expect(texts, contains('stop, cyclist right'));
      expect(texts, isNot(contains('slippery surface')));
      expect(
        svc.queueSnapshot.every((j) => j.priority == SpeechPriority.critical),
        isTrue,
      );
    });
  });

  group('TtsService queue — priority ordering', () {
    test('warning drops info but leaves critical alone', () {
      final svc = TtsService.forTesting();
      svc.say('stop, pothole', SpeechPriority.critical);
      svc.say('arriving soon', SpeechPriority.info);
      svc.say('low battery', SpeechPriority.warning);

      final byPriority = <SpeechPriority, int>{};
      for (final j in svc.queueSnapshot) {
        byPriority[j.priority] = (byPriority[j.priority] ?? 0) + 1;
      }
      expect(byPriority[SpeechPriority.critical], 1);
      expect(byPriority[SpeechPriority.warning], 1);
      expect(byPriority[SpeechPriority.info] ?? 0, 0);
    });

    test('queue stays sorted by priority descending after mixed enqueue', () {
      final svc = TtsService.forTesting();
      svc.say('arriving soon', SpeechPriority.info);
      svc.say('low battery', SpeechPriority.warning);

      final snap = svc.queueSnapshot;
      for (int i = 0; i < snap.length - 1; i++) {
        expect(
          snap[i].priority.index,
          greaterThanOrEqualTo(snap[i + 1].priority.index),
          reason:
              'queue must remain sorted by priority descending (index ${snap[i].priority} vs ${snap[i + 1].priority})',
        );
      }
    });

    test('info stream bounded by queue overflow policy', () {
      final svc = TtsService.forTesting();
      for (int i = 0; i < 10; i++) {
        svc.say('info $i', SpeechPriority.info);
      }
      
      
      expect(svc.queueSnapshot.length, lessThanOrEqualTo(4));
    });
  });

  group('TtsService queue — OPT-07 follow-up stale eviction', () {
    test(
        'pruneStaleCriticals drops only the critical that has outlived the '
        'supplied freshness window', () async {
      final svc = TtsService.forTesting();
      svc.say('stale warning', SpeechPriority.critical);

      
      
      
      
      await Future<void>.delayed(const Duration(milliseconds: 120));
      svc.say('fresh warning', SpeechPriority.critical);
      expect(svc.queueSnapshot, hasLength(2));

      svc.pruneStaleCriticalsForTesting(
        DateTime.now(),
        maxAge: const Duration(milliseconds: 80),
      );

      expect(svc.queueSnapshot, hasLength(1));
      expect(svc.queueSnapshot.single.text, 'fresh warning');
    });

    test('pruneStaleCriticals never removes non-critical jobs', () {
      final svc = TtsService.forTesting();
      
      
      svc.say('first warning', SpeechPriority.warning);
      svc.say('second warning', SpeechPriority.warning);
      expect(svc.queueSnapshot, hasLength(2));

      svc.pruneStaleCriticalsForTesting(
        DateTime.now().add(const Duration(seconds: 60)),
      );

      
      
      expect(svc.queueSnapshot, hasLength(2));
      expect(
        svc.queueSnapshot.every((j) => j.priority != SpeechPriority.critical),
        isTrue,
      );
    });

    test(
      'Safety audit 1.2: pruneStaleCriticals without an explicit maxAge is a '
      'no-op — life-threatening alerts are never silently dropped',
      () {
        
        
        
        
        
        
        final svc = TtsService.forTesting();
        svc.say('Stop! car approaching', SpeechPriority.critical);
        svc.say('Stop! pothole ahead', SpeechPriority.critical);
        expect(svc.queueSnapshot, hasLength(2));

        
        svc.pruneStaleCriticalsForTesting(
          DateTime.now().add(const Duration(hours: 1)),
        );

        expect(
          svc.queueSnapshot,
          hasLength(2),
          reason:
              'Safety audit 1.2: critical alerts must never be dropped by a '
              'default-aged prune pass. The old 4 s default would silently '
              'discard a queued "Stop!" while a long info utterance was '
              'mid-speech.',
        );
        expect(
          svc.queueSnapshot.map((j) => j.text).toSet(),
          {'Stop! car approaching', 'Stop! pothole ahead'},
        );
      },
    );
  });

  group('TtsService queue — trackId eviction', () {
    test('evictTrack removes non-critical jobs for that track', () {
      final svc = TtsService.forTesting();
      svc.say('person ahead', SpeechPriority.warning, trackId: 42);
      svc.say('other alert', SpeechPriority.warning, trackId: 7);

      svc.evictTrack(42);

      expect(svc.queueSnapshot, hasLength(1));
      expect(svc.queueSnapshot.single.trackId, 7);
    });

    test('evictTrack preserves critical jobs even for the evicted track', () {
      final svc = TtsService.forTesting();
      svc.say('stop, car', SpeechPriority.critical, trackId: 42);

      svc.evictTrack(42);

      expect(svc.queueSnapshot, hasLength(1));
      expect(svc.queueSnapshot.single.priority, SpeechPriority.critical);
    });
  });
}
