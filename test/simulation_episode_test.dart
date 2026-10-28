import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/simulation/simulation_episode.dart';

class _Episode extends StatefulWidget {
  final int index;
  final List<String> events;
  final bool removeRoute;
  const _Episode(this.index, this.events, {this.removeRoute = false});
  @override
  State<_Episode> createState() => _EpisodeState();
}

class _EpisodeState extends State<_Episode> {
  @override
  void dispose() {
    widget.events.add('dispose-${widget.index}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(
      onPressed: () {
        if (widget.removeRoute) {
          Navigator.of(context).removeRoute(ModalRoute.of(context)!);
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Text('finish-${widget.index}'),
    ),
  );
}

void main() {
  for (final mode in [(true, true), (true, false), (false, false)]) {
    final automatic = mode.$1;
    testWidgets(
      'two episodes dispose before reuse, automatic=$automatic remove=${mode.$2}',
      (tester) async {
        final events = <String>[];
        var finished = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    for (var i = 0; i < 2; i++) {
                      events.add('open-$i');
                      await runSimulationEpisode(
                        context: context,
                        automatic: automatic,
                        builder: (_) =>
                            _Episode(i, events, removeRoute: mode.$2),
                      );
                      events.add('closed-$i');
                    }
                    finished = true;
                  },
                  child: const Text('start'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('start'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('finish-0'));
        await tester.pumpAndSettle();
        expect(find.text('finish-1'), findsOneWidget);
        expect(events, ['open-0', 'dispose-0', 'closed-0', 'open-1']);
        await tester.tap(find.text('finish-1'));
        await tester.pumpAndSettle();
        expect(finished, true);
        expect(events.last, 'closed-1');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('timed-out automatic episode is removed and reports failure', (
    tester,
  ) async {
    final events = <String>[];
    Object? failure;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                try {
                  await runSimulationEpisode(
                    context: context,
                    automatic: true,
                    timeout: const Duration(milliseconds: 100),
                    builder: (_) => _Episode(0, events),
                  );
                } catch (error) {
                  failure = error;
                }
              },
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(failure, isA<Exception>());
    expect(events, ['dispose-0']);
    expect(find.text('finish-0'), findsNothing);
    expect(find.text('start'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
