import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/task.dart';
import 'todo_list_service.dart';

// handles all reads/writes to the tasks collection in firestore
class FirestoreService {
  final CollectionReference _taskRef = FirebaseFirestore.instance.collection(
    'tasks',
  );
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // [ s e s s i o n   g u a r d ]
  // grabs the active user's UID or blocks the operation if no one is logged in
  String get _requireUid {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Authentication required to access tasks.');
    }
    return uid;
  }

  // [ act3: ubac verification for ownership]
  // prevents IDOR by verifying the logged-in user's UID matches the task's ownerId
  // (or verifies list membership if the task belongs to a collaborative list)
  Future<void> _verifyOwnership(Task task) async {
    final uid = _requireUid;
    if (task.listId != null) {
      await TodoListService().verifyMembership(task.listId!);
      return;
    }
    if (task.ownerId != uid) {
      throw StateError('403 Forbidden: You do not own this task.');
    }
  }

  // CREATE - adding a Task, stamping the logged-in user's UID as ownerId
  Future<void> addTask(Task task) async {
    final uid = _requireUid;
    // force ownerId to be the authenticated user's UID so it cannot be spoofed
    final ownedTask = task.copyWith(ownerId: uid);
    if (ownedTask.listId != null) {
      await TodoListService().verifyMembership(ownedTask.listId!);
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

    // if a collaborative list is selected, query tasks belonging to that listId;
    // otherwise query personal tasks where ownerId == uid
    final query = (listId != null && listId.isNotEmpty)
        ? _taskRef.where('listId', isEqualTo: listId)
        : _taskRef.where('ownerId', isEqualTo: uid);

    // [ u b a c   q u e r y   f i l t e r ]
    return query.snapshots().map((snapshot) {
      final tasks = snapshot.docs
          .map(
            (doc) => Task.fromMap(doc.id, doc.data() as Map<String, dynamic>),
          )
          .where(
            (task) =>
                task.deletedAt == null &&
                (listId != null ? task.listId == listId : task.listId == null),
          )
          .toList();

      // sort newest first in memory to avoid requiring a composite index
      tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return tasks;
    });
  }

  // [ c a l e n d a r   m e r g e d   s t r e a m ]
  // Streams all personal tasks + all tasks from the user's collaborative lists,
  // merged and deduplicated by task ID.
  Stream<List<Task>> streamAllUserAndCollabTasks(List<String> collabListIds) {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return Stream.value(const []);
    }

    // If the user has no collaborative lists, only stream their owned tasks
    if (collabListIds.isEmpty) {
      return _taskRef.where('ownerId', isEqualTo: uid).snapshots().map((snap) {
        final tasks = snap.docs
            .map((d) => Task.fromMap(d.id, d.data() as Map<String, dynamic>))
            .where((t) => t.deletedAt == null)
            .toList();
        tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return tasks;
      });
    }

    // Merge owned tasks + collaborative list tasks reactively
    final validIds = collabListIds.take(30).toList();
    return _taskRef
        .where(
          Filter.or(
            Filter('ownerId', isEqualTo: uid),
            Filter('listId', whereIn: validIds),
          ),
        )
        .snapshots()
        .map((snap) {
          final Map<String, Task> byId = {};
          for (final doc in snap.docs) {
            final task = Task.fromMap(
              doc.id,
              doc.data() as Map<String, dynamic>,
            );
            if (task.deletedAt != null) continue;
            // keep personal tasks or tasks belonging to one of the user's collab lists
            if (task.listId == null || validIds.contains(task.listId)) {
              byId[task.id] = task;
            }
          }
          final merged = byId.values.toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return merged;
        });
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

  // UPDATE - saving edited task fields
  Future<void> updateTask(Task task) async {
    await _verifyOwnership(task);
    await _taskRef.doc(task.id).update(task.toMap());
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
