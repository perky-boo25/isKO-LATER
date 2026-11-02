import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models/task.dart';
import '../services/firestore_service.dart';

// [ act4: s h a r e d   t a s k   &   e r r o r   h e l p e r s ]
// Consolidates duplicated sorting, date-stripping, friendly error translation,
// and task card mutation handlers previously repeated in HomeScreen & CalendarScreen.
abstract final class TaskHelpers {
  /// Strips the time component from [date] so tasks on the same calendar day
  /// group together regardless of hour or minute.
  static DateTime dayOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  /// Returns `true` if [date] falls on today's local calendar date.
  static bool isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  /// Places incomplete tasks at the top and pushes completed tasks to the bottom,
  /// ordering completed tasks chronologically by `completedAt`.
  static List<Task> sortWithDoneAtBottom(List<Task> input) {
    final notDone = input.where((t) => !t.isDone).toList();
    final done = input.where((t) => t.isDone).toList()
      ..sort((a, b) {
        final aTime = a.completedAt ?? DateTime(0);
        final bTime = b.completedAt ?? DateTime(0);
        return aTime.compareTo(bTime);
      });
    return [...notDone, ...done];
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this task?'),
        content: Text('Move "${task.title}" to deleted items?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

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
