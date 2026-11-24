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

// email to pre-fill on the login screen. The profile screen sets it after an
// email change is verified; LoginScreen reads it once and clears it.
final ValueNotifier<String?> loginEmailPrefill = ValueNotifier<String?>(null);

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

      // if the email was changed and the DB write didn't make it earlier,
      // this catches the users/{uid} document up (fire-and-forget)
      syncProfileToFirestore();
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e));
    }
  }

  // [ r e - a u t h e n t i c a t e ]
  // proves the person at the keyboard knows the CURRENT password before a
  // sensitive change (an unlocked, still-logged-in phone isn't enough)
  Future<void> _reauthenticate(String currentPassword) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw AuthException('No active session.');
    }
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: currentPassword),
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-credential' || e.code == 'wrong-password') {
        throw AuthException('Current password is incorrect.');
      }
      throw AuthException(_messageFor(e));
    }
  }

  // [ u p d a t e   p r o f i l e ]
  // name: applied immediately.
  // email: needs the current password, then firebase emails a verification
  // link to the NEW address; the email only changes once that link is opened.
  Future<String> updateProfile({
    required String newName,
    required String newEmail,
    String? currentPassword,
  }) async {
    final user = currentUser;
    if (user == null) throw AuthException('No active session.');

    final nameChanged = newName != (user.displayName?.trim() ?? '');
    final emailChanged =
        newEmail.toLowerCase() != (user.email ?? '').toLowerCase();
    String message = 'Changes saved.';

    try {
      // 1. email first: it's the step most likely to fail
      if (emailChanged) {
        if (currentPassword == null || currentPassword.isEmpty) {
          throw AuthException(
            'Enter your current password to change your email.',
          );
        }
        await _reauthenticate(currentPassword);
        await user.verifyBeforeUpdateEmail(newEmail);
        message =
            'Verification link sent to $newEmail. '
            'Your email updates once you tap it.';
      }

      // 2. name applies immediately (no verification needed)
      if (nameChanged) {
        await user.updateDisplayName(newName);
        await _userRef.doc(user.uid).update({'userName': newName});
        if (!emailChanged) message = 'Username updated.';
      }

      if (nameChanged) await user.reload();
      return message;
    } on AuthException {
      rethrow; // already friendly (e.g. wrong current password)
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw AuthException(
          'That email is already used by another account. '
          'Please use a different one.',
        );
      }
      if (e.code == 'requires-recent-login') {
        throw AuthException('Please log in again to change your email.');
      }
      throw AuthException(_messageFor(e));
    } catch (_) {
      throw AuthException('Could not save changes. Please try again.');
    }
  }

  // [ e m a i l   c h a n g e   v e r i f i e d ? ]
  // Polled by the profile screen while it waits for the user to tap the link.
  // Returns true once the change has gone through, after updating the
  // Firestore users/{uid} document.
  //
  // How we know: when the email changes, firebase revokes the old session, so
  // either reload() shows the new email, reload() fails with
  // user-token-expired, or the user is already signed out.
  Future<bool> completeEmailChangeIfVerified({
    required String uid,
    required String newEmail,
  }) async {
    final user = _auth.currentUser;
    bool changed;

    if (user == null) {
      changed = true; // session already ended by firebase
    } else {
      try {
        await user.reload();
        changed =
            (_auth.currentUser?.email ?? '').toLowerCase() ==
            newEmail.toLowerCase();
      } on FirebaseAuthException catch (e) {
        changed =
            e.code == 'user-token-expired' || e.code == 'invalid-user-token';
      }
    }

    if (!changed) return false;

    // DB update. Best effort: if the session is already gone this can be
    // denied, and syncProfileToFirestore() fixes it at the next login.
    try {
      await _userRef.doc(uid).update({'email': newEmail});
    } catch (e) {
      debugPrint('Email DB update deferred to next login: $e');
    }
    return true;
  }

  // [ s y n c   p r o f i l e ]
  // after the user taps the verification link, Auth has the new email but
  // Firestore doesn't. Call after login / when the profile opens.
  Future<void> syncProfileToFirestore() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await user.reload();
      final fresh = _auth.currentUser;
      if (fresh == null) return;

      final doc = await _userRef.doc(fresh.uid).get();
      final data = doc.data() as Map<String, dynamic>?;
      if (data != null && data['email'] == fresh.email) {
        return; // already in sync
      }
      await _userRef.doc(fresh.uid).set({
        'email': fresh.email,
        'userName': fresh.displayName ?? data?['userName'] ?? '',
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Profile sync skipped: $e'); // non-critical, retry next time
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
