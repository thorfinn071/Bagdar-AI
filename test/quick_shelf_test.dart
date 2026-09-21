import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/models/strings.dart';
import 'package:bagdar/theme/bagdar_theme.dart';
import 'package:bagdar/theme/bagdar_tokens.dart';
import 'package:bagdar/widgets/a11y/bottom_shelf_tab.dart';
import 'package:bagdar/widgets/quick_shelf.dart';

Widget _wrap(Widget child, {BagdarThemeName theme = BagdarThemeName.dark}) {
  return MaterialApp(
    theme: BagdarTheme.buildMaterialTheme(theme),
    home: BagdarTheme(
      name: theme,
      colors: BagdarColors.of(theme),
      child: Scaffold(
        body: Align(alignment: Alignment.bottomCenter, child: child),
      ),
    ),
  );
}

void main() {
  setUp(() => AppStrings.setLanguage(AppLanguage.ru));

  group('QuickShelf rendering', () {
    testWidgets('renders three tabs with short visible labels (RU)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(QuickShelf(activeTask: ShelfTask.camera, onTaskSelected: (_) {})),
      );

      expect(find.byType(BottomShelfTab), findsNWidgets(3));
      expect(find.text(S.get('shelf_camera_short')), findsOneWidget);
      expect(find.text(S.get('shelf_read_short')), findsOneWidget);
      expect(find.text(S.get('shelf_navigate_short')), findsOneWidget);
    });

    testWidgets(
      'TalkBack semantic label is the long action-oriented sentence',
      (tester) async {
        AppStrings.setLanguage(AppLanguage.en);
        await tester.pumpWidget(
          _wrap(
            QuickShelf(activeTask: ShelfTask.camera, onTaskSelected: (_) {}),
          ),
        );

        expect(
          find.bySemanticsLabel('Read aloud what the camera sees.'),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel('Set a route by voice.'), findsOneWidget);
        expect(find.bySemanticsLabel('Camera. Active.'), findsOneWidget);
      },
    );

    testWidgets('reflects active tab via Semantics.selected', (tester) async {
      AppStrings.setLanguage(AppLanguage.en);
      await tester.pumpWidget(
        _wrap(QuickShelf(activeTask: ShelfTask.read, onTaskSelected: (_) {})),
      );

      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Read aloud what the camera sees.'),
        ),
        isSemantics(
          label: 'Read aloud what the camera sees.',
          isButton: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('inactive tabs are NOT marked selected', (tester) async {
      AppStrings.setLanguage(AppLanguage.en);
      await tester.pumpWidget(
        _wrap(QuickShelf(activeTask: ShelfTask.camera, onTaskSelected: (_) {})),
      );

      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Read aloud what the camera sees.'),
        ),
        isSemantics(
          label: 'Read aloud what the camera sees.',
          isButton: true,
          isSelected: false,
          hasTapAction: true,
        ),
      );
    });
  });

  group('QuickShelf interaction', () {
    testWidgets('tapping Read tab fires onTaskSelected(ShelfTask.read)', (
      tester,
    ) async {
      ShelfTask? captured;
      await tester.pumpWidget(
        _wrap(
          QuickShelf(
            activeTask: ShelfTask.camera,
            onTaskSelected: (t) => captured = t,
          ),
        ),
      );

      await tester.tap(find.text(S.get('shelf_read_short')));
      await tester.pump();

      expect(captured, ShelfTask.read);
    });

    testWidgets('tapping Navigate tab fires onTaskSelected(navigate)', (
      tester,
    ) async {
      ShelfTask? captured;
      await tester.pumpWidget(
        _wrap(
          QuickShelf(
            activeTask: ShelfTask.camera,
            onTaskSelected: (t) => captured = t,
          ),
        ),
      );

      await tester.tap(find.text(S.get('shelf_navigate_short')));
      await tester.pump();

      expect(captured, ShelfTask.navigate);
    });

    testWidgets('tapping Camera tab fires onTaskSelected(camera)', (
      tester,
    ) async {
      ShelfTask? captured;
      await tester.pumpWidget(
        _wrap(
          QuickShelf(
            activeTask: ShelfTask.read,
            onTaskSelected: (t) => captured = t,
          ),
        ),
      );

      await tester.tap(find.text(S.get('shelf_camera_short')));
      await tester.pump();

      expect(captured, ShelfTask.camera);
    });
  });

  group('QuickShelf size constraints', () {
    testWidgets('shelf height equals BagdarSpacing.shelfHeight', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(QuickShelf(activeTask: ShelfTask.camera, onTaskSelected: (_) {})),
      );

      final shelfFinder = find.byType(QuickShelf);
      final size = tester.getSize(shelfFinder);
      expect(size.height, BagdarSpacing.shelfHeight);
    });

    testWidgets('every tab has at least 64dp tap height', (tester) async {
      await tester.pumpWidget(
        _wrap(QuickShelf(activeTask: ShelfTask.camera, onTaskSelected: (_) {})),
      );

      for (var i = 0; i < 3; i++) {
        final size = tester.getSize(find.byType(BottomShelfTab).at(i));
        expect(
          size.height,
          greaterThanOrEqualTo(BagdarSpacing.tapMinimum),
          reason: 'tab $i height ${size.height} < ${BagdarSpacing.tapMinimum}',
        );
      }
    });
  });

  group('QuickShelf in different themes', () {
    testWidgets('renders without errors under all 4 themes', (tester) async {
      for (final theme in BagdarThemeName.values) {
        await tester.pumpWidget(
          _wrap(
            QuickShelf(activeTask: ShelfTask.camera, onTaskSelected: (_) {}),
            theme: theme,
          ),
        );
        expect(find.byType(QuickShelf), findsOneWidget);
        expect(find.byType(BottomShelfTab), findsNWidgets(3));
      }
    });
  });
}
