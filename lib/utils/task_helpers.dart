import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models/task.dart';
import '../services/firestore_service.dart';
import '../widgets/confirm_dialog.dart';

// [ act4: s h a r e d   t a s k   &   e r r o r   h e l p e r s ]
// Consolidates duplicated sorting, date-stripping, friendly error translation,
// and task card mutation handlers previously repeated in HomeScreen & CalendarScreen.
abstract final class TaskHelpers {
  /// Strips the time component from [date] so tasks on the same calendar day
  /// group together regardless of hour or minute.
  static DateTime dayOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  /// Returns `true` if [date] falls on today's local calendar date.
  static bool isToday(DateTime date, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    return date.year == ref.year &&
        date.month == ref.month &&
        date.day == ref.day;
  }

  /// Returns `true` if [task] is still incomplete and its `dueDateTime` has passed.
  static bool isOverdue(Task task, {DateTime? now}) {
    if (task.isDone) return false;
    final ref = now ?? DateTime.now();
    return task.dueDateTime.isBefore(ref);
  }

  /// Returns `true` if [date] falls on a calendar day strictly after today.
  static bool isFutureDay(DateTime date, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    return dayOnly(date).isAfter(dayOnly(ref));
  }

  /// Single-pass comparator that orders tasks for optimal UX:
  /// 1. Incomplete tasks (`!isDone`) always appear above completed tasks (`isDone`).
  /// 2. Incomplete tasks are ordered by soonest `dueDateTime`, breaking ties by
  ///    highest `Priority` (`high` -> `medium` -> `low`).
  /// 3. Completed tasks are ordered by most recently completed (`completedAt` desc),
  ///    treating a pending `serverTimestamp()` (`null`) as `now` to prevent UI flicker.
  static List<Task> sortWithDoneAtBottom(List<Task> input) {
    final now = DateTime.now();
    final sorted = List<Task>.of(input);

    sorted.sort((a, b) {
      // 1. Group incomplete tasks above completed tasks
      if (a.isDone != b.isDone) {
        return a.isDone ? 1 : -1;
      }

      // 2. Both incomplete: earliest deadline first, then highest priority first
      if (!a.isDone) {
        final dueComparison = a.dueDateTime.compareTo(b.dueDateTime);
        if (dueComparison != 0) return dueComparison;
        // Priority enum is { low (0), medium (1), high (2) } -> descending index
        return b.priority.index.compareTo(a.priority.index);
      }

      // 3. Both completed: most recently finished first (avoids year-0 flicker)
      final aCompleted = a.completedAt ?? now;
      final bCompleted = b.completedAt ?? now;
      return bCompleted.compareTo(aCompleted);
    });

    return sorted;
  }

  /// Converts raw Dart/Firebase exceptions into safe, user-friendly feedback
  /// so raw stack traces, `Bad state:` prefixes, or internal error codes never
  /// leak directly to end users.
  static String friendlyError(
    Object error, {
    String fallback = 'Something went wrong. Please try again.',
  }) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'You do not have permission to perform this action.';
        case 'unavailable':
          return 'Network unavailable. Changes will sync when back online.';
        case 'not-found':
          return 'This item no longer exists.';
        default:
          return fallback;
      }
    }

    if (error is StateError) {
      // StateError.toString() prefixes messages with "Bad state: "
      return error.message;
    }

    final raw = error.toString().replaceFirst('Bad state: ', '').trim();
    if (raw.isEmpty || raw.startsWith('Instance of')) {
      return fallback;
    }
    return raw;
  }

  /// Shared handler for toggling a task's completion status with friendly error SnackBar.
  static Future<void> toggleTaskDone(
    BuildContext context, {
    required Task task,
    required FirestoreService service,
  }) async {
    try {
      await service.toggleTaskDone(task);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  /// Shared handler for confirming task deletion, soft-deleting in Firestore,
  /// and presenting an Undo action SnackBar.
  static Future<void> confirmAndSoftDelete(
    BuildContext context, {
    required Task task,
    required FirestoreService service,
  }) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Delete this task?',
      message:
          '"${task.title}" will be removed from your list. You can still tap Undo right after.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline_rounded,
    );

    if (!confirmed || !context.mounted) return;

    // Capture ScaffoldMessenger before awaiting Firestore so Undo still shows
    // even if removing the task disposes the item widget on the current day.
    final messenger = ScaffoldMessenger.of(context);
    try {
      await service.softDelete(task);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Task deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              service.undoDelete(task).catchError((Object e) {
                messenger.showSnackBar(
                  SnackBar(content: Text(friendlyError(e))),
                );
              });
            },
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }
}
