import 'package:cloud_firestore/cloud_firestore.dart';

// [ c o l l a b o r a t i v e   l i s t   m o d e l ]
// normalized schema for shared to-do lists stored in DB
// stores only user UIDs (ownerId + memberIds) to avoid duplicating user data.
class TodoList {
  final String id;
  final String name;

  // UID of the user who created and owns this collaborative list
  final String ownerId;

  // UIDs of all users allowed to view and manage tasks in this list
  // (always includes ownerId plus any invited collaborators)
  final List<String> memberIds;
  final DateTime createdAt;

  TodoList({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.memberIds,
    required this.createdAt,
  });

  // helper to check if a given user UID is the owner of this list
  bool isOwnedBy(String uid) => ownerId == uid;

  // helper to check if a given user UID is a member of this list
  bool hasMember(String uid) => memberIds.contains(uid);

  // TodoList -> Map so it can be written to Firestore
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'ownerId': ownerId,
      'memberIds': memberIds,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  // rebuilds a TodoList from a Firestore document (map + doc id)
  factory TodoList.fromMap(String id, Map<String, dynamic> map) {
    final rawMembers = map['memberIds'] as List<dynamic>? ?? const [];
    return TodoList(
      id: id,
      name: map['name'] as String? ?? 'Untitled List',
      ownerId: map['ownerId'] as String? ?? '',
      memberIds: rawMembers.map((e) => e.toString()).toList(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
