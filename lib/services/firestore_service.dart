import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/task.dart';
import '../utils/input_sanitizer.dart';
import 'todo_list_service.dart';

// handles all reads and writes to the `tasks` collection in Firestore
class FirestoreService {
  static const int _kWhereInMax = 30;

  final CollectionReference _taskRef = FirebaseFirestore.instance.collection(
    'tasks',
  );
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TodoListService _todoListService = TodoListService();

  // returns the active user's UID or throws if signed out
  String get _requireUid {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Authentication required to access tasks.');
    }
    return uid;
  }

  // verifies task ownership (personal) or list membership (collaborative)
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

  // deserializes snapshot docs, skips soft-deleted tasks, and sorts newest first
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

  // CREATE - stamps the logged-in user's UID as ownerId and validates input
  Future<void> addTask(Task task) async {
    final uid = _requireUid;
    final safeTitle = InputSanitizer.enforceSafeText(
      task.title,
      fieldName: 'Title',
    );
    final ownedTask = task.copyWith(ownerId: uid, title: safeTitle);
    if (ownedTask.listId != null) {
      await _todoListService.verifyMembership(ownedTask.listId!);
    }
    await _taskRef.add(ownedTask.toMap());
  }

  // READ - live stream of personal tasks (listId == null) or shared list tasks
  Stream<List<Task>> streamTasks({String? listId}) {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return Stream.value(const []);
    }

    final isCollabList = listId != null && listId.isNotEmpty;
    final query = isCollabList
        ? _taskRef.where('listId', isEqualTo: listId)
        : _taskRef.where('ownerId', isEqualTo: uid);

    return query.snapshots().map(
      (snapshot) => _parseAndSortTasks(
        snapshot,
        include: (task) =>
            isCollabList ? task.listId == listId : task.listId == null,
      ),
    );
  }

  // READ - merged stream of personal tasks + collaborative list tasks for Calendar
  Stream<List<Task>> streamAllUserAndCollabTasks(List<String> collabListIds) {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return Stream.value(const []);
    }

    final validIds = collabListIds.toSet().take(_kWhereInMax).toList();
    if (validIds.isEmpty) {
      return _taskRef.where('ownerId', isEqualTo: uid).snapshots().map(
            (snap) => _parseAndSortTasks(
              snap,
              include: (task) => task.listId == null,
            ),
          );
    }

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

  // UPDATE - toggles task completion status
  Future<void> toggleTaskDone(Task task) async {
    await _verifyOwnership(task);
    final newIsDone = !task.isDone;
    await _taskRef.doc(task.id).update({
      'isDone': newIsDone,
      'completedAt': newIsDone ? FieldValue.serverTimestamp() : null,
    });
  }

  // UPDATE - sends only mutable form fields to reduce payload size
  Future<void> updateTask(Task task) async {
    await _verifyOwnership(task);
    final safeTitle = InputSanitizer.enforceSafeText(
      task.title,
      fieldName: 'Title',
    );
    await _taskRef.doc(task.id).update({
      'title': safeTitle,
      'dueDateTime': Timestamp.fromDate(task.dueDateTime),
      'priority': task.priority.name,
      'tag': task.tag.name,
    });
  }

  // DELETE - soft-deletes a task by stamping deletedAt
  Future<void> softDelete(Task task) async {
    await _verifyOwnership(task);
    await _taskRef.doc(task.id).update({
      'deletedAt': FieldValue.serverTimestamp(),
    });
  }

  // UNDO DELETE - restores a soft-deleted task
  Future<void> undoDelete(Task task) async {
    await _verifyOwnership(task);
    await _taskRef.doc(task.id).update({'deletedAt': null});
  }
}
