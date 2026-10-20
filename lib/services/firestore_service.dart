import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/task.dart';

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
  // before allowing any update, toggle, or delete operation
  void _verifyOwnership(Task task) {
    final uid = _requireUid;
    if (task.ownerId != uid) {
      throw StateError('403 Forbidden: You do not own this task.');
    }
  }

  // CREATE - adding a Task, stamping the logged-in user's UID as ownerId
  Future<void> addTask(Task task) async {
    final uid = _requireUid;
    // force ownerId to be the authenticated user's UID so it cannot be spoofed
    final ownedTask = task.copyWith(ownerId: uid);
    await _taskRef.add(ownedTask.toMap());
  }

  // READ - a live stream of ONLY the logged-in user's personal tasks (recent first)
  Stream<List<Task>> streamTasks() {
    final uid = _auth.currentUser?.uid;
    // if logged out, emit an empty list immediately instead of querying all tasks
    if (uid == null || uid.isEmpty) {
      return Stream.value(const []);
    }

    // query filter
    // server-side filter: Firestore only returns documents where ownerId == uid
    return _taskRef.where('ownerId', isEqualTo: uid).snapshots().map((
      snapshot,
    ) {
      final tasks = snapshot.docs
          .map(
            (doc) => Task.fromMap(doc.id, doc.data() as Map<String, dynamic>),
          )
          // exclude soft-deleted tasks and collaborative list tasks from Personal view
          .where((task) => task.deletedAt == null && task.listId == null)
          .toList();

      // sort newest first in memory to avoid requiring a composite index
      tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return tasks;
    });
  }

  // UPDATE - toggling completion state
  Future<void> toggleTaskDone(Task task) async {
    _verifyOwnership(task);
    final newIsDone = !task.isDone;
    await _taskRef.doc(task.id).update({
      'isDone': newIsDone,
      'completedAt': newIsDone ? FieldValue.serverTimestamp() : null,
    });
  }

  // UPDATE - saving edited task fields
  Future<void> updateTask(Task task) async {
    _verifyOwnership(task);
    await _taskRef.doc(task.id).update(task.toMap());
  }

  // DELETE - soft-deleting a task
  Future<void> softDelete(Task task) async {
    _verifyOwnership(task);
    await _taskRef.doc(task.id).update({
      'deletedAt': FieldValue.serverTimestamp(),
    });
  }

  // UNDO DELETE - restoring a soft-deleted task
  Future<void> undoDelete(Task task) async {
    _verifyOwnership(task);
    await _taskRef.doc(task.id).update({'deletedAt': null});
  }
}
