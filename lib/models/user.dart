import 'package:cloud_firestore/cloud_firestore.dart';

//NOTE: no password becuase firebase stores and hashed it
class AppUser {
  final String uid;
  final String email;
  final String userName;
  final DateTime createdAt;

  AppUser({
    required this.uid,
    required this.email,
    required this.userName,
    required this.createdAt,
  });

  // mapping User so it can be written to Firestore
  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'userName': userName,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  //rebuilds User from Firestore doc (map + uid)
  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    return AppUser(
      uid: uid,
      email: map['email'] as String,
      userName: map['userName'] as String,
      createdAt: (map['createdAt'] as Timestamp).toDate(),
    );
  }

  // [FOR PROFILE PAGE] - return copy with changed fields
  AppUser copyWith({String? email, String? userName}) {
    return AppUser(
      uid: uid,
      email: email ?? this.email,
      userName: userName ?? this.userName,
      createdAt: createdAt,
    );
  }
}