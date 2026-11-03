import 'package:flutter_test/flutter_test.dart';

import 'package:isko_later/models/task.dart';
import 'package:isko_later/models/todo_list.dart';
import 'package:isko_later/utils/task_helpers.dart';
import 'package:isko_later/widgets/auth_widgets.dart';

// [ act4: replaced broken template counter test with model & helper unit tests ]
void main() {
  group('TaskHelpers & UBAC Model Unit Tests', () {
    test(
      'sortWithDoneAtBottom orders incomplete by due time & priority, and completed by most recent',
      () {
        final now = DateTime(2026, 11, 3, 10, 0);
        final doneOlder = Task(
          id: 'done_older',
          ownerId: 'u1',
          title: 'Done Earlier',
          dueDateTime: now,
          priority: Priority.low,
          tag: TaskTags.personal,
          isDone: true,
          createdAt: now,
          completedAt: now.add(const Duration(minutes: 2)),
        );
        final doneNewer = Task(
          id: 'done_newer',
          ownerId: 'u1',
          title: 'Done Recently',
          dueDateTime: now,
          priority: Priority.medium,
          tag: TaskTags.others,
          isDone: true,
          createdAt: now,
          completedAt: now.add(const Duration(minutes: 10)),
        );
        final pendingLowSameTime = Task(
          id: 'pending_low',
          ownerId: 'u1',
          title: 'Pending Low',
          dueDateTime: now.add(const Duration(hours: 1)),
          priority: Priority.low,
          tag: TaskTags.school,
          isDone: false,
          createdAt: now,
        );
        final pendingHighSameTime = Task(
          id: 'pending_high',
          ownerId: 'u1',
          title: 'Pending High',
          dueDateTime: now.add(const Duration(hours: 1)),
          priority: Priority.high,
          tag: TaskTags.school,
          isDone: false,
          createdAt: now,
        );

        final sorted = TaskHelpers.sortWithDoneAtBottom([
          doneOlder,
          pendingLowSameTime,
          doneNewer,
          pendingHighSameTime,
        ]);

        expect(sorted.map((t) => t.id).toList(), [
          'pending_high',
          'pending_low',
          'done_newer',
          'done_older',
        ]);
      },
    );

    test('TodoList ownership and membership helpers enforce UBAC checks', () {
      final list = TodoList(
        id: 'list_1',
        name: 'CMSC 128 Group',
        ownerId: 'uid_owner',
        memberIds: ['uid_owner', 'uid_collab'],
        createdAt: DateTime(2026, 11, 3),
      );

      expect(list.isOwnedBy('uid_owner'), isTrue);
      expect(list.isOwnedBy('uid_collab'), isFalse);
      expect(list.hasMember('uid_collab'), isTrue);
      expect(list.hasMember('uid_stranger'), isFalse);
    });

    test('AuthValidators reject malformed emails and short passwords', () {
      expect(AuthValidators.email(''), isNotNull);
      expect(AuthValidators.email('not-an-email'), isNotNull);
      expect(AuthValidators.email('student@up.edu.ph'), isNull);

      expect(AuthValidators.newPassword('short'), isNotNull);
      expect(AuthValidators.newPassword('validPass123'), isNull);
    });

    test('isOverdue flags only incomplete past-deadline tasks', () {
      final now = DateTime(2026, 11, 3, 12, 0);
      final overdueTask = Task(
        id: 't_overdue',
        ownerId: 'u1',
        title: 'Missed quiz',
        dueDateTime: now.subtract(const Duration(hours: 2)),
        priority: Priority.high,
        tag: TaskTags.school,
        isDone: false,
        createdAt: now,
      );
      final completedPastTask = overdueTask.copyWith(isDone: true);
      final futureTask = overdueTask.copyWith(
        dueDateTime: now.add(const Duration(days: 1)),
      );

      expect(TaskHelpers.isOverdue(overdueTask, now: now), isTrue);
      expect(TaskHelpers.isOverdue(completedPastTask, now: now), isFalse);
      expect(TaskHelpers.isOverdue(futureTask, now: now), isFalse);
      expect(TaskHelpers.isFutureDay(futureTask.dueDateTime, now: now), isTrue);
    });

    test('friendlyError strips raw Dart StateError prefixes', () {
      final err = StateError('403 Forbidden: You do not own this task.');
      expect(
        TaskHelpers.friendlyError(err),
        '403 Forbidden: You do not own this task.',
      );
    });
  });
}
