import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/task.dart';

// handles all reads/writes to the tasks collection in firestore
class FirestoreService {
  final CollectionReference _taskRef = FirebaseFirestore.instance.collection(
    'tasks',
  );
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // returns the active user's UID or throws if no one is logged in
  String get _requireUid {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Authentication required to access tasks.');
    }
    return uid;
  }

  // verifies the current user owns the task before mutating it
  void _verifyOwnership(Task task) {
    final uid = _requireUid;
    if (task.ownerId != uid) {
      throw StateError('Error: You do not own this task.');
    }
  }

  // CREATE - adding a Task scoped to the logged-in user
  Future<void> addTask(Task task) async {
    final uid = _requireUid;
    final ownedTask = task.copyWith(ownerId: uid);
    await _taskRef.add(ownedTask.toMap());
  }

  // READ - a live stream of the logged-in user's personal tasks (recent first)
  Stream<List<Task>> streamTasks() {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return Stream.value(const []);
    }

    return _taskRef.where('ownerId', isEqualTo: uid).snapshots().map((
      snapshot,
    ) {
      final tasks = snapshot.docs
          .map(
            (doc) => Task.fromMap(doc.id, doc.data() as Map<String, dynamic>),
          )
          .where((task) => task.deletedAt == null && task.listId == null)
          .toList();

      tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return tasks;
    });
  }

  //UPDATE
  Future<void> toggleTaskDone(Task task) async {
    _verifyOwnership(task);
    final newIsDone = !task.isDone;
    await _taskRef.doc(task.id).update({
      'isDone': newIsDone,
      'completedAt': newIsDone ? FieldValue.serverTimestamp() : null,
    });
  }

  Future<void> updateTask(Task task) async {
    _verifyOwnership(task);
    await _taskRef.doc(task.id).update(task.toMap());
  }

  // DELETE
  Future<void> softDelete(Task task) async {
    _verifyOwnership(task);
    await _taskRef.doc(task.id).update({
      'deletedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> undoDelete(Task task) async {
    _verifyOwnership(task);
    await _taskRef.doc(task.id).update({'deletedAt': null});
  }
}
