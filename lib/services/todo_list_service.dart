import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/todo_list.dart';
import '../models/user.dart';

// [ a c t i v e   l i s t   s t a t e ]
// Holds the currently selected list ID across HomeScreen, CalendarScreen, and AddEditTaskSheet.
// null = Personal To-Do List; non-null = Collaborative TodoList document ID.
final ValueNotifier<String?> activeListId = ValueNotifier<String?>(null);

// [ c o l l a b o r a t i v e   l i s t   s e r v i c e ]
// Handles all reads/writes to `todo_lists` and member lookups in `users`.
// Separated from FirestoreService so personal task CRUD stays clean and modular.
class TodoListService {
  // Firestore caps `whereIn` clauses at 30 values and WriteBatch commits at 500 ops.
  static const int _kWhereInMax = 30;
  static const int _kBatchMax = 500;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late final CollectionReference _listRef = _db.collection('todo_lists');
  late final CollectionReference _taskRef = _db.collection('tasks');
  late final CollectionReference _userRef = _db.collection('users');
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // grabs the active user's UID or throws if logged out
  String get _requireUid {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError(
        'Authentication required to access collaborative lists.',
      );
    }
    return uid;
  }

  // Safely parses a `users/{uid}` document even if `createdAt` was omitted
  // during a profile sync (`syncProfileToFirestore`).
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

  // [ u b a c   m e m b e r s h i p   c h e c k ]
  // Verifies that the logged-in user is in `todo_lists/{listId}.memberIds`
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

  // READ - live stream of collaborative lists where the logged-in user is in memberIds.
  // Users NEVER receive lists they have not been added to.
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
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw StateError('List name cannot be empty.');
    }

    final newList = TodoList(
      id: '',
      name: cleanName,
      ownerId: uid,
      memberIds: [uid], // owner is the initial member
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

  // UPDATE - allows ONLY the list owner to invite another user by username or email
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

    // 1. Fetch list and enforce owner-only check (UBAC)
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

    // 2. [ act4: fast-path indexed email lookup before full collection scan ]
    // When inviting via exact email (e.g. tapping "Invite" on a suggested user),
    // query only that 1 matching user doc instead of reading all `users` docs.
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

    // Fallback: case-insensitive / partial username or email search
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

    // 3. Add target user's UID to memberIds array
    await _listRef.doc(listId).update({
      'memberIds': FieldValue.arrayUnion([matchedUser.uid]),
    });

    return matchedUser;
  }

  // UPDATE - allows ONLY the list owner to remove a collaborator from memberIds
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

  // DELETE - allows ONLY the list owner to delete a collaborative list and its tasks
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

    // 1. [ act4: atomic WriteBatch replaces N+1 sequential per-task deletes ]
    // Must commit task deletions while `todo_lists/{listId}` still exists so
    // `isListMember(resource.data.listId)` in firestore.rules passes cleanly.
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

    // 2. Delete the collaborative list document itself
    await _listRef.doc(listId).delete();

    // 3. Reset activeListId to Personal list if viewing the deleted list
    if (activeListId.value == listId) {
      activeListId.value = null;
    }
  }

  // READ - fetches all registered AppUsers from `users` for live autocomplete suggestions
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

  // [ act4: eliminated N+1 sequential member lookup using batched `whereIn` ]
  // READ - resolves member UIDs into AppUser objects from `users/{uid}` in a
  // single batched query per 30 UIDs instead of looping `doc(uid).get()` N times,
  // while keeping user names/emails normalized out of task/list documents.
  Future<List<AppUser>> getListMembers(List<String> memberIds) async {
    if (memberIds.isEmpty) return const [];
    _requireUid;

    // Deduplicate UIDs before querying, then chunk by Firestore's 30-item whereIn limit
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

    // Preserve the original memberIds ordering (owner first, then invited members)
    return [
      for (final id in memberIds)
        if (usersByUid.containsKey(id)) usersByUid[id]!,
    ];
  }
}
