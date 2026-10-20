import 'package:cloud_firestore/cloud_firestore.dart';

enum Priority { low, medium, high }

enum TaskTags { school, personal, others }

// data model - needed for one task/ to-do item
class Task {
  final String id;
  // [act3: adding foreign keys]
  // ownerId links this task to users/{uid} (who created/owns this task)
  final String ownerId;
  // listId is null for Personal tasks, or references todo_lists/{listId} for Collaborative tasks
  final String? listId;
  final String title;
  final DateTime dueDateTime;
  final Priority priority;
  final TaskTags tag;
  final bool isDone;
  final DateTime createdAt;
  final DateTime? deletedAt;
  final DateTime? completedAt;

  //constructor - builds a task
  Task({
    required this.id,
    // required at compile time so a task can never be created without an owner
    required this.ownerId,
    this.listId,
    required this.title,
    required this.dueDateTime,
    required this.priority,
    required this.tag,
    this.isDone = false,
    required this.createdAt,
    this.deletedAt,
    this.completedAt,
  });

  // task -> Map so it can be written to Firestore
  Map<String, dynamic> toMap() {
    return {
      // persist ownerId and listId in Firestore for ubac query filtering & security rules
      'ownerId': ownerId,
      'listId': listId,
      'title': title,
      'dueDateTime': Timestamp.fromDate(dueDateTime),
      'priority': priority.name,
      'tag': tag.name,
      'isDone': isDone,
      'createdAt': Timestamp.fromDate(createdAt),
      'deletedAt': deletedAt != null ? Timestamp.fromDate(deletedAt!) : null,
      'completedAt': completedAt != null
          ? Timestamp.fromDate(completedAt!)
          : null,
    };
  }

  // rebuilds a task from a firestore document (map + its id)
  factory Task.fromMap(String id, Map<String, dynamic> map) {
    return Task(
      id: id,
      // fallback to empty string if reading legacy pre-ubac documents
      ownerId: map['ownerId'] as String? ?? '',
      listId: map['listId'] as String?,
      title: map['title'] as String,
      dueDateTime: (map['dueDateTime'] as Timestamp).toDate(),
      priority: Priority.values.byName(map['priority'] as String),
      tag: TaskTags.values.byName(map['tag'] as String),
      isDone: map['isDone'] as bool? ?? false,
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      deletedAt: (map['deletedAt'] as Timestamp?)?.toDate(),
      completedAt: (map['completedAt'] as Timestamp?)?.toDate(),
    );
  }

  // for edit purposes - return a copy of specific fields
  Task copyWith({
    String? ownerId,
    String? listId,
    bool clearListId = false,
    String? title,
    DateTime? dueDateTime,
    Priority? priority,
    TaskTags? tag,
    bool? isDone,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) {
    return Task(
      id: id,
      // preserve existing ownerId and listId unless explicitly overridden
      ownerId: ownerId ?? this.ownerId,
      listId: clearListId ? null : (listId ?? this.listId),
      title: title ?? this.title,
      dueDateTime: dueDateTime ?? this.dueDateTime,
      priority: priority ?? this.priority,
      tag: tag ?? this.tag,
      isDone: isDone ?? this.isDone,
      createdAt: createdAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    );
  }
}
