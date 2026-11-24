import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/todo_list.dart';
import '../models/user.dart';
import '../utils/input_sanitizer.dart';

// currently selected list ID (`null` = Personal To-Do List, non-null = shared list ID)
final ValueNotifier<String?> activeListId = ValueNotifier<String?>(null);

// handles all reads/writes to `todo_lists` and member lookups in `users`
class TodoListService {
  static const int _kWhereInMax = 30;
  static const int _kBatchMax = 500;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late final CollectionReference _listRef = _db.collection('todo_lists');
  late final CollectionReference _taskRef = _db.collection('tasks');
  late final CollectionReference _userRef = _db.collection('users');
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _requireUid {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError(
        'Authentication required to access collaborative lists.',
      );
    }
    return uid;
  }

  // parses a `users/{uid}` doc safely even if `createdAt` was omitted during sync
  AppUser _safeUserFromMap(String uid, Map<String, dynamic> map) {
    final rawCreatedAt = map['createdAt'];
    return AppUser(
      uid: uid,
      email: (map['email'] as String?) ?? '',
      userName: (map['userName'] as String?) ?? 'User',
      createdAt: rawCreatedAt is Timestamp
          ? rawCreatedAt.toDate()
          : DateTime.now(),
    );
  }

  // verifies that the logged-in user is in `todo_lists/{listId}.memberIds`
  Future<void> verifyMembership(String listId) async {
    final uid = _requireUid;
    final listDoc = await _listRef.doc(listId).get();
    if (!listDoc.exists) {
      throw StateError('404 Not Found: Collaborative list no longer exists.');
    }
    final list = TodoList.fromMap(
      listDoc.id,
      listDoc.data() as Map<String, dynamic>,
    );
    if (!list.hasMember(uid)) {
      throw StateError(
        '403 Forbidden: You are not a member of this collaborative list.',
      );
    }
  }

  // READ - streams collaborative lists where the logged-in user is a member
  Stream<List<TodoList>> streamCollaborativeLists() {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return Stream.value(const []);
    }

    return _listRef
        .where('memberIds', arrayContains: uid)
        .snapshots()
        .map((snapshot) {
          final lists = snapshot.docs
              .map(
                (doc) => TodoList.fromMap(
                  doc.id,
                  doc.data() as Map<String, dynamic>,
                ),
              )
              .toList();

          lists.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return lists;
        });
  }

  // CREATE - creates a new collaborative list owned by currentUser
  Future<TodoList> createCollaborativeList(String name) async {
    final uid = _requireUid;
    final cleanName = InputSanitizer.enforceSafeText(
      name,
      fieldName: 'List name',
      maxLength: 100,
    );

    final newList = TodoList(
      id: '',
      name: cleanName,
      ownerId: uid,
      memberIds: [uid],
      createdAt: DateTime.now(),
    );

    final docRef = await _listRef.add(newList.toMap());
    return TodoList(
      id: docRef.id,
      name: newList.name,
      ownerId: newList.ownerId,
      memberIds: newList.memberIds,
      createdAt: newList.createdAt,
    );
  }

  // UPDATE - owner-only invite by username or email
  Future<AppUser> addMemberByEmailOrUsername({
    required String listId,
    required String identifier,
  }) async {
    final uid = _requireUid;
    final trimmed = identifier.trim();
    final queryText = trimmed.toLowerCase();
    if (queryText.isEmpty) {
      throw StateError('Please enter a username or email.');
    }

    final listDoc = await _listRef.doc(listId).get();
    if (!listDoc.exists) {
      throw StateError('Collaborative list not found.');
    }
    final list = TodoList.fromMap(
      listDoc.id,
      listDoc.data() as Map<String, dynamic>,
    );
    if (!list.isOwnedBy(uid)) {
      throw StateError('403 Forbidden: Only the list owner can add members.');
    }

    // fast-path: indexed email lookup before falling back to collection scan
    AppUser? matchedUser;
    if (trimmed.contains('@')) {
      final exactEmailSnap = await _userRef
          .where('email', isEqualTo: trimmed)
          .limit(1)
          .get();
      if (exactEmailSnap.docs.isNotEmpty) {
        final doc = exactEmailSnap.docs.first;
        matchedUser = _safeUserFromMap(
          doc.id,
          doc.data() as Map<String, dynamic>,
        );
      }
    }

    // fallback: case-insensitive / partial username or email search
    if (matchedUser == null) {
      final usersSnapshot = await _userRef.get();
      AppUser? exactMatch;
      AppUser? partialMatch;

      for (final doc in usersSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;
        final email = (data['email'] as String? ?? '').trim().toLowerCase();
        final userName =
            (data['userName'] as String? ?? '').trim().toLowerCase();
        final candidate = _safeUserFromMap(doc.id, data);

        if (email == queryText || userName == queryText) {
          exactMatch = candidate;
          break;
        }
        if (partialMatch == null &&
            !list.hasMember(candidate.uid) &&
            (email.contains(queryText) || userName.contains(queryText))) {
          partialMatch = candidate;
        }
      }
      matchedUser = exactMatch ?? partialMatch;
    }

    if (matchedUser == null) {
      throw StateError('No registered user found matching "$identifier".');
    }

    if (list.hasMember(matchedUser.uid)) {
      throw StateError('${matchedUser.userName} is already in this list.');
    }

    await _listRef.doc(listId).update({
      'memberIds': FieldValue.arrayUnion([matchedUser.uid]),
    });

    return matchedUser;
  }

  // UPDATE - owner-only collaborator removal
  Future<void> removeMemberFromList({
    required String listId,
    required String memberUid,
  }) async {
    final uid = _requireUid;
    final listDoc = await _listRef.doc(listId).get();
    if (!listDoc.exists) {
      throw StateError('Collaborative list not found.');
    }
    final list = TodoList.fromMap(
      listDoc.id,
      listDoc.data() as Map<String, dynamic>,
    );
    if (!list.isOwnedBy(uid)) {
      throw StateError(
        '403 Forbidden: Only the list owner can remove members.',
      );
    }
    if (memberUid == list.ownerId) {
      throw StateError('The list owner cannot be removed from their own list.');
    }

    await _listRef.doc(listId).update({
      'memberIds': FieldValue.arrayRemove([memberUid]),
    });
  }

  // DELETE - owner-only cascade delete of tasks (via WriteBatch) and the list doc
  Future<void> deleteCollaborativeList(String listId) async {
    final uid = _requireUid;
    final listDoc = await _listRef.doc(listId).get();
    if (!listDoc.exists) {
      throw StateError('Collaborative list not found.');
    }
    final list = TodoList.fromMap(
      listDoc.id,
      listDoc.data() as Map<String, dynamic>,
    );
    if (!list.isOwnedBy(uid)) {
      throw StateError(
        '403 Forbidden: Only the list owner can delete this list.',
      );
    }

    final tasksSnap = await _taskRef.where('listId', isEqualTo: listId).get();
    final taskDocs = tasksSnap.docs;
    for (var i = 0; i < taskDocs.length; i += _kBatchMax) {
      final batch = _db.batch();
      final end = (i + _kBatchMax < taskDocs.length)
          ? i + _kBatchMax
          : taskDocs.length;
      for (var j = i; j < end; j++) {
        batch.delete(taskDocs[j].reference);
      }
      await batch.commit();
    }

    await _listRef.doc(listId).delete();

    if (activeListId.value == listId) {
      activeListId.value = null;
    }
  }

  // READ - fetches registered users for collaborator autocomplete suggestions
  Future<List<AppUser>> getAllUsers() async {
    _requireUid;
    final snap = await _userRef.get();
    final List<AppUser> users = [];
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data != null) {
        users.add(_safeUserFromMap(doc.id, data));
      }
    }
    users.sort(
      (a, b) => a.userName.toLowerCase().compareTo(b.userName.toLowerCase()),
    );
    return users;
  }

  // READ - resolves member UIDs in batches of 30 (`whereIn`) to avoid N+1 queries
  Future<List<AppUser>> getListMembers(List<String> memberIds) async {
    if (memberIds.isEmpty) return const [];
    _requireUid;

    final uniqueIds = memberIds.toSet().toList();
    final List<Future<QuerySnapshot>> chunkQueries = [];
    for (var i = 0; i < uniqueIds.length; i += _kWhereInMax) {
      final chunk = uniqueIds.sublist(
        i,
        i + _kWhereInMax < uniqueIds.length
            ? i + _kWhereInMax
            : uniqueIds.length,
      );
      chunkQueries.add(
        _userRef.where(FieldPath.documentId, whereIn: chunk).get(),
      );
    }

    final snapshots = await Future.wait(chunkQueries);
    final Map<String, AppUser> usersByUid = {};
    for (final snap in snapshots) {
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null) {
          usersByUid[doc.id] = _safeUserFromMap(doc.id, data);
        }
      }
    }

    return [
      for (final id in memberIds)
        if (usersByUid.containsKey(id)) usersByUid[id]!,
    ];
  }
}
