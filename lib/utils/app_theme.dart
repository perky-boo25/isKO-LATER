import 'package:flutter/material.dart';

import '../models/task.dart';

// [ act4: c e n t r a l i z e d   d e s i g n   t o k e n s ]
// Extracted from screens and widgets to eliminate magic hex literals, ensure
// visual consistency across all views, and simplify future theme adjustments.
abstract final class AppColors {

  static const Color espresso = Color(0xFF4A3427);
  static const Color terracotta = Color(0xFFC65A42);
  static const Color creamHeader = Color(0xFFFCE8CB);
  static const Color creamSurface = Color(0xFFFFF8EF);
  static const Color profileSurface = Color(0xFFFBF8F4);
  static const Color navSelectedFill = Color(0xFFF1DDBE);
  static const Color oliveAccent = Color(0xFF6B7F5E);
  static const Color errorRed = Color(0xFFB3261E);
  static const Color logoutAmber = Color(0xFFE48C10);

  // [ t a s k   p r i o r i t y   &   t a g   m a p p e r s ]
  // single source of truth previously duplicated in TaskCard, AddEditTaskSheet,
  // and CalendarScreen (resolving the medium-priority color inconsistency).

  /// Maps a [Priority] enum value to its consistent indicator color across the app.
  static Color priorityColor(Priority priority) {
    switch (priority) {
      case Priority.high:
        return Colors.pinkAccent;
      case Priority.medium:
        return const Color(0xFFE8873A);
      case Priority.low:
        return Colors.blueAccent;
    }
  }

  // capitalized label for a [Priority] level (e.g., "High")
  static String priorityLabel(Priority priority) {
    return '${priority.name[0].toUpperCase()}${priority.name.substring(1)}';
  }

  // Maps a [TaskTags] enum value to its corresponding Material icon.
  static IconData tagIcon(TaskTags tag) {
    switch (tag) {
      case TaskTags.school:
        return Icons.school;
      case TaskTags.personal:
        return Icons.person;
      case TaskTags.others:
        return Icons.label_outline;
    }
  }

  // capitalized human-readable label for a [TaskTags] category (e.g., "School")
  static String tagLabel(TaskTags tag) {
    return '${tag.name[0].toUpperCase()}${tag.name.substring(1)}';
  }
}
