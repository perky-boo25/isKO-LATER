import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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

  // emits on auth state + profile edits (display name, email) so UI updates live
  Stream<User?> get userChanges => _auth.userChanges();

  // [ R E G I S T E R]
  // create auth acc -> set username -> save to firestore
  // if the profile save fails, the auth account is deleted again, so a failed
  // sign up never leaves anyone logged in (and AuthGate never shows Home)
  Future<void> register({
    required String userName,
    required String email,
    required String password,
  }) async {
    //clean input first
    final cleanName = userName.trim();
    final cleanEmail = email.trim();

    // step 1: create the auth account (this also signs the user in)
    final UserCredential credential;
    try {
      credential = await _auth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e));
    }

    final user = credential.user!;

    // step 2: save the name + profile. If ANYTHING fails here, undo step 1
    try {
      await user.updateDisplayName(cleanName);

      // sync profile doc to db
      final appUser = AppUser(
        uid: user.uid,
        email: user.email ?? cleanEmail,
        userName: cleanName,
        createdAt: DateTime.now(),
      );
      await _userRef.doc(user.uid).set(appUser.toMap());
    } catch (e) {
      debugPrint('Profile save failed, rolling back: $e');

      // deleting the account also signs the user out;
      // if the delete itself fails, at least sign out
      try {
        await user.delete();
      } catch (_) {
        await _auth.signOut();
      }

      throw AuthException(
        'We could not finish creating your account. Please try again.',
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

  // [ p a s s w o r d   r e s e t ]
  // sends single-use reset link via firebase hosted email flow
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      // account enumeration protection: silently absorb missing user errors
      // prevents leaking whether an email exists in the database
      if (e.code == 'user-not-found') return;
      throw AuthException(_messageFor(e));
    }
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
