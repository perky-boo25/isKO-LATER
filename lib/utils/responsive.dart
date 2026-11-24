import 'package:flutter/material.dart';

// [ r e s p o n s i v e   h e l p e r ]
// scales layout sizes via MediaQuery.sizeOf so UI fits any phone screen ratio
abstract final class Responsive {
  static const double _narrowWidth = 360.0;
  static const double _compactHeight = 700.0;
  static const double _shortHeight = 560.0;
  static const double _wideWidth = 600.0;

  static Size size(BuildContext context) => MediaQuery.sizeOf(context);

  static bool isNarrow(BuildContext context) =>
      size(context).width < _narrowWidth;

  static bool isCompactHeight(BuildContext context) =>
      size(context).height < _compactHeight;

  static bool isShortViewport(BuildContext context) =>
      size(context).height < _shortHeight;

  static bool isWideScreen(BuildContext context) =>
      size(context).width >= _wideWidth;

  // tighter side margins on narrow (<360dp) screens
  static double horizontalPadding(BuildContext context) =>
      isNarrow(context) ? 14.0 : 20.0;

  // shrinks top banner padding on shorter phone screens
  static EdgeInsets headerPadding(BuildContext context) {
    final hPad = horizontalPadding(context);
    if (isShortViewport(context)) return EdgeInsets.fromLTRB(hPad, 10, hPad, 12);
    if (isCompactHeight(context)) return EdgeInsets.fromLTRB(hPad, 12, hPad, 16);
    return EdgeInsets.fromLTRB(hPad, 16, hPad, 22);
  }

  // scales large serif header text down on compact screens
  static double headerTitleSize(BuildContext context, {double base = 30.0}) {
    if (isShortViewport(context)) return base * 0.78;
    if (isCompactHeight(context) || isNarrow(context)) return base * 0.86;
    return base;
  }

  // ~40% of screen height (clamped) so the task list below the calendar isn't cut off
  static double calendarHeight(BuildContext context) =>
      (size(context).height * 0.40).clamp(230.0, 350.0);

  // scales illustrations to screen height so buttons below stay visible
  static double illustrationHeight(
    BuildContext context, {
    double ratio = 0.24,
    double min = 96.0,
    double max = 220.0,
  }) => (size(context).height * ratio).clamp(min, max);

  // centers content with a max width on tablets/wide windows
  static Widget constrainWidth(
    BuildContext context, {
    required Widget child,
    double maxWidth = 640.0,
  }) {
    if (!isWideScreen(context)) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
