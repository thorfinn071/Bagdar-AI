import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/theme/bagdar_theme.dart';
import 'package:bagdar/theme/bagdar_tokens.dart';
import 'package:bagdar/widgets/a11y/stepper_field.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: BagdarTheme.buildMaterialTheme(BagdarThemeName.dark),
    home: BagdarTheme(
      name: BagdarThemeName.dark,
      colors: BagdarColors.dark,
      child: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    ),
  );
}

String _percent(double v) => '${(v * 100).round()}%';
String _times(double v) => '${v.toStringAsFixed(1)}x';

void main() {
  group('StepperField rendering', () {
    testWidgets('shows label, current value, and ± buttons', (tester) async {
      await tester.pumpWidget(
        _wrap(
          StepperField(
            label: 'Speech rate',
            value: 1.0,
            min: 0.6,
            max: 1.5,
            divisions: 9,
            formatValue: _times,
            onChanged: (_) {},
          ),
        ),
      );

      expect(find.text('Speech rate'), findsOneWidget);
      expect(find.text('1.0x'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.remove), findsOneWidget);
    });

    testWidgets('progress bar reflects normalized value', (tester) async {
      await tester.pumpWidget(
        _wrap(
          StepperField(
            label: 'Volume',
            value: 0.75,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            formatValue: _percent,
            onChanged: (_) {},
          ),
        ),
      );

      final progress = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progress.value, closeTo(0.75, 0.001));
    });
  });

  group('StepperField interaction', () {
    testWidgets('+ button increments by one step and snaps', (tester) async {
      double captured = 0.5;
      await tester.pumpWidget(
        _wrap(
          StepperField(
            label: 'Volume',
            value: captured,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            formatValue: _percent,
            onChanged: (v) => captured = v,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      expect(captured, closeTo(0.6, 0.001));
    });

    testWidgets('− button decrements by one step', (tester) async {
      double captured = 0.5;
      await tester.pumpWidget(
        _wrap(
          StepperField(
            label: 'Volume',
            value: captured,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            formatValue: _percent,
            onChanged: (v) => captured = v,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();

      expect(captured, closeTo(0.4, 0.001));
    });

    testWidgets('+ at max does NOT fire onChanged', (tester) async {
      bool changed = false;
      await tester.pumpWidget(
        _wrap(
          StepperField(
            label: 'Volume',
            value: 1.0,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            formatValue: _percent,
            onChanged: (_) => changed = true,
          ),
        ),
      );

      
      await tester.tap(find.byIcon(Icons.add), warnIfMissed: false);
      await tester.pump();

      expect(changed, isFalse);
    });

    testWidgets('− at min does NOT fire onChanged', (tester) async {
      bool changed = false;
      await tester.pumpWidget(
        _wrap(
          StepperField(
            label: 'Volume',
            value: 0.0,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            formatValue: _percent,
            onChanged: (_) => changed = true,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.remove), warnIfMissed: false);
      await tester.pump();

      expect(changed, isFalse);
    });
  });

  group('StepperField semantics', () {
    testWidgets('renders human-readable label and formatted value',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          StepperField(
            label: 'Speech rate',
            value: 1.2,
            min: 0.6,
            max: 1.5,
            divisions: 9,
            formatValue: _times,
            onChanged: (_) {},
          ),
        ),
      );

      
      expect(find.text('Speech rate'), findsOneWidget);
      expect(find.text('1.2x'), findsOneWidget);
    });

    testWidgets('+/- buttons expose accessibility-friendly button semantics',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          StepperField(
            label: 'Volume',
            value: 0.5,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            formatValue: _percent,
            onChanged: (_) {},
            increaseSemanticLabel: 'Increase volume',
            decreaseSemanticLabel: 'Decrease volume',
          ),
        ),
      );

      expect(find.bySemanticsLabel('Increase volume'), findsOneWidget);
      expect(find.bySemanticsLabel('Decrease volume'), findsOneWidget);
    });
  });
}
