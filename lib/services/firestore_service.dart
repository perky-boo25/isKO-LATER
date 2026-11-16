import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/task.dart';
import 'todo_list_service.dart';

// handles all reads/writes to the tasks collection in firestore
class FirestoreService {
  // Firestore caps `whereIn` clauses inside `Filter.or` at 30 items.
  static const int _kWhereInMax = 30;

  final CollectionReference _taskRef = FirebaseFirestore.instance.collection(
    'tasks',
  );
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // [ act4: reuse single TodoListService instance instead of recreating per call ]
  final TodoListService _todoListService = TodoListService();

  // [ s e s s i o n   g u a r d ]
  // grabs the active user's UID or blocks the operation if no one is logged in
  String get _requireUid {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Authentication required to access tasks.');
    }
    return uid;
  }

  // [ act3: ubac verification for ownership ]
  // prevents IDOR by verifying the logged-in user's UID matches the task's ownerId
  // (or verifies list membership if the task belongs to a collaborative list)
  Future<void> _verifyOwnership(Task task) async {
    final uid = _requireUid;
    if (task.listId != null) {
      await _todoListService.verifyMembership(task.listId!);
      return;
    }
    if (task.ownerId != uid) {
      throw StateError('403 Forbidden: You do not own this task.');
    }
  }

  // [ act4: centralized snapshot parser & sorter ]
  // Deduplicates Task.fromMap deserialization, soft-delete filtering, ID
  // deduplication, and newest-first sorting across personal and merged streams.
  List<Task> _parseAndSortTasks(
    QuerySnapshot snapshot, {
    required bool Function(Task task) include,
  }) {
    final Map<String, Task> byId = {};
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      final task = Task.fromMap(doc.id, data);
      if (task.deletedAt != null) continue;
      if (include(task)) {
        byId[task.id] = task;
      }
    }

    final tasks = byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return tasks;
  }

  // CREATE - adding a Task, stamping the logged-in user's UID as ownerId
  Future<void> addTask(Task task) async {
    final uid = _requireUid;
    // force ownerId to be the authenticated user's UID so it cannot be spoofed
    final ownedTask = task.copyWith(ownerId: uid, title: task.title.trim());
    if (ownedTask.listId != null) {
      await _todoListService.verifyMembership(ownedTask.listId!);
    }
    await _taskRef.add(ownedTask.toMap());
  }

  // READ - a live stream of the logged-in user's personal tasks (or shared list tasks)
  Stream<List<Task>> streamTasks({String? listId}) {
    final uid = _auth.currentUser?.uid;
    // if logged out, emit an empty list immediately instead of querying all tasks
    if (uid == null || uid.isEmpty) {
      return Stream.value(const []);
    }

    final isCollabList = listId != null && listId.isNotEmpty;

    // if a collaborative list is selected, query tasks belonging to that listId;
    // otherwise query personal tasks where ownerId == uid
    final query = isCollabList
        ? _taskRef.where('listId', isEqualTo: listId)
        : _taskRef.where('ownerId', isEqualTo: uid);

    // [ u b a c   q u e r y   f i l t e r ]
    return query.snapshots().map(
      (snapshot) => _parseAndSortTasks(
        snapshot,
        include: (task) =>
            isCollabList ? task.listId == listId : task.listId == null,
      ),
    );
  }

  // [ c a l e n d a r   m e r g e d   s t r e a m ]
  // Streams all personal tasks + all tasks from the user's collaborative lists,
  // merged and deduplicated by task ID in a single `Filter.or` query.
  Stream<List<Task>> streamAllUserAndCollabTasks(List<String> collabListIds) {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return Stream.value(const []);
    }

    final validIds = collabListIds.toSet().take(_kWhereInMax).toList();

    // If the user has no collaborative lists, only stream their owned personal tasks
    if (validIds.isEmpty) {
      return _taskRef.where('ownerId', isEqualTo: uid).snapshots().map(
            (snap) => _parseAndSortTasks(
              snap,
              include: (task) => task.listId == null,
            ),
          );
    }

    // Merge owned tasks + collaborative list tasks reactively in 1 query
    return _taskRef
        .where(
          Filter.or(
            Filter('ownerId', isEqualTo: uid),
            Filter('listId', whereIn: validIds),
          ),
        )
        .snapshots()
        .map(
          (snap) => _parseAndSortTasks(
            snap,
            include: (task) =>
                task.listId == null || validIds.contains(task.listId),
          ),
        );
  }

  // UPDATE - toggling completion state
  Future<void> toggleTaskDone(Task task) async {
    await _verifyOwnership(task);
    final newIsDone = !task.isDone;
    await _taskRef.doc(task.id).update({
      'isDone': newIsDone,
      'completedAt': newIsDone ? FieldValue.serverTimestamp() : null,
    });
  }

  // [ act4: payload optimization — send only mutable form fields ]
  // UPDATE - saves edited task fields without re-sending immutable ownership
  // (`ownerId`, `listId`, `createdAt`) or overwriting concurrent `isDone` state.
  Future<void> updateTask(Task task) async {
    await _verifyOwnership(task);
    await _taskRef.doc(task.id).update({
      'title': task.title.trim(),
      'dueDateTime': Timestamp.fromDate(task.dueDateTime),
      'priority': task.priority.name,
      'tag': task.tag.name,
    });
  }

  // DELETE - soft-deleting a task
  Future<void> softDelete(Task task) async {
    await _verifyOwnership(task);
    await _taskRef.doc(task.id).update({
      'deletedAt': FieldValue.serverTimestamp(),
    });
  }

  // UNDO DELETE - restoring a soft-deleted task
  Future<void> undoDelete(Task task) async {
    await _verifyOwnership(task);
    await _taskRef.doc(task.id).update({'deletedAt': null});
  }
}
