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
// Handles all reads/writes to todo_lists and member lookups in users.
// Separated from FirestoreService so personal task CRUD stays clean and modular.
class TodoListService {
  final CollectionReference _listRef = FirebaseFirestore.instance.collection(
    'todo_lists',
  );
  final CollectionReference _userRef = FirebaseFirestore.instance.collection(
    'users',
  );
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

  // [  m e m b e r s h i p   c h e c k ]
  // Verifies that the logged-in user is in todo_lists/{listId}.memberIds
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

    return _listRef.where('memberIds', arrayContains: uid).snapshots().map((
      snapshot,
    ) {
      final lists = snapshot.docs
          .map(
            (doc) =>
                TodoList.fromMap(doc.id, doc.data() as Map<String, dynamic>),
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
    final queryText = identifier.trim().toLowerCase();
    if (queryText.isEmpty) {
      throw StateError('Please enter a username or email.');
    }

    // 1. Fetch list and enforce owner-only check
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

    // 2. Look up target user in `users` collection by email or userName (case-insensitive)
    final usersSnapshot = await _userRef.get();
    AppUser? matchedUser;
    for (final doc in usersSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final email = (data['email'] as String? ?? '').trim().toLowerCase();
      final userName = (data['userName'] as String? ?? '').trim().toLowerCase();
      if (email == queryText || userName == queryText) {
        matchedUser = AppUser.fromMap(doc.id, data);
        break;
      }
    }

    if (matchedUser == null) {
      throw StateError('No registered user found with "$identifier".');
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

  // READ - resolves member UIDs into AppUser objects from `users/{uid}`
  // so user names/emails are never duplicated inside task or list documents
  Future<List<AppUser>> getListMembers(List<String> memberIds) async {
    final List<AppUser> members = [];
    for (final memberUid in memberIds) {
      final doc = await _userRef.doc(memberUid).get();
      if (doc.exists && doc.data() != null) {
        members.add(
          AppUser.fromMap(doc.id, doc.data() as Map<String, dynamic>),
        );
      }
    }
    return members;
  }
}
