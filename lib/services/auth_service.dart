import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user.dart';

// show simple error message; catches e to show the message
// why? no Firebase error code leaks to UI
class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final CollectionReference _userRef = FirebaseFirestore.instance.collection(
    'users',
  );

  // listen to real time auth state (logged in or logged out)
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // grabing CURRENT USER snapshot
  User? get currentUser => _auth.currentUser;

  // [ R E G I S T E R]
  // create auth acc -> set username -> save to firestore
  Future<void> register({
    required String userName,
    required String email,
    required String password,
  }) async {
    //clean input first
    final cleanName = userName.trim();
    final cleanEmail = email.trim();

    try {
      // make auth record (autochecks for duplicate email)
      final credential = await _auth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );

      final user = credential.user!;

      // update auth profile name
      await user.updateDisplayName(cleanName);

      // sync profile doc to db
      final appUser = AppUser(
        uid: user.uid,
        email: user.email ?? cleanEmail,
        userName: cleanName,
        createdAt: DateTime.now(),
      );

      await _userRef.doc(user.uid).set(appUser.toMap());
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e));
    } on FirebaseException {
      // edge case: auth passed but firestore write choked
      throw AuthException(
        'Your account was created, but we could not save your profile.'
        'Please try logging in.',
      );
    }
  }

  // [ l o g i n ]
  //validates cred against server-side hash
  Future<void> login({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e));
    }
  }

  // [ l o g o u t]
  // clears session
  Future<void> logout() async {
    await _auth.signOut();
  }

  // translate firebase error codes to human-readable text
  String _messageFor(FirebaseAuthException e) {
    switch (e.code) {
      // register errors
      case 'email-already-in-use':
        return 'An account with this email already exists. Try logging in instead.';
      case 'invalid-email':
        return 'That email address does not look right. Please check it.';
      case 'weak-password':
        return 'Password is too weak. Use at least 8 characters.';

      // login errors: keep vague so no email leaking
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Incorrect email or password.';

      // general errors
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
