import 'package:flutter/material.dart';

import '../models/strings.dart';
import '../theme/bagdar_theme.dart';
import '../theme/bagdar_tokens.dart';
import 'a11y/bottom_shelf_tab.dart';

/// Active task on the camera-as-home surface. Distinct from
/// [AppMode] (street / cane / scan) — mode is *behavioural*,
/// task is the user-selected action (read text, navigate, etc.).
enum ShelfTask { camera, read, navigate }

/// 3-tab bottom shelf shown at the foot of the camera screen for
/// low-vision and sighted-helper users. Hidden entirely when
/// pitch-black UI is active so blind users see a fully empty screen.
///
/// The shelf is **not** bottom-navigation: there is only one screen
/// and the tabs invoke modes/actions on that screen. Tabs are
/// labelled with verbs ("Read", "Navigate") to make this clear.
///
/// Composition:
/// - 72 dp tall (see [BagdarSpacing.shelfHeight])
/// - 1 dp top divider in the active theme's `divider` token
/// - SafeArea bottom inset honoured
class QuickShelf extends StatelessWidget {
  final ShelfTask activeTask;
  final ValueChanged<ShelfTask> onTaskSelected;

  const QuickShelf({
    super.key,
    required this.activeTask,
    required this.onTaskSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    return SafeArea(
      top: false,
      child: Container(
        height: BagdarSpacing.shelfHeight,
        decoration: BoxDecoration(
          color: colors.surfaceBg,
          border: Border(top: BorderSide(color: colors.divider, width: 1)),
        ),
        child: Row(
          children: [
            Expanded(
              child: BottomShelfTab(
                label: S.get('shelf_camera_short'),
                semanticLabel: S.get('shelf_camera_label'),
                hint: S.get('shelf_camera_hint'),
                icon: Icons.photo_camera_outlined,
                active: activeTask == ShelfTask.camera,
                onActivate: () => onTaskSelected(ShelfTask.camera),
              ),
            ),
            Expanded(
              child: BottomShelfTab(
                label: S.get('shelf_read_short'),
                semanticLabel: S.get('shelf_read_label'),
                hint: S.get('shelf_read_hint'),
                icon: Icons.menu_book_outlined,
                active: activeTask == ShelfTask.read,
                onActivate: () => onTaskSelected(ShelfTask.read),
              ),
            ),
            Expanded(
              child: BottomShelfTab(
                label: S.get('shelf_navigate_short'),
                semanticLabel: S.get('shelf_navigate_label'),
                hint: S.get('shelf_navigate_hint'),
                icon: Icons.navigation_outlined,
                active: activeTask == ShelfTask.navigate,
                onActivate: () => onTaskSelected(ShelfTask.navigate),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
