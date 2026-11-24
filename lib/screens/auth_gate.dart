import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';

// [ a u t h   g a t e ]
// root entry point (MaterialApp.home) routing users by session state:
//   - signed in  -> protected screens (HomeScreen)
//   - signed out -> public flow (LoginScreen)
// handles 3 key requirements:
//   (1) session persistence (skips login on app reopen if token exists)
//   (2) route protection (unauthenticated users can't render protected pages)
//   (3) live auth reactive swap (switching pages instantly on login / logout)

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<User?> _authStream = AuthService().authStateChanges;

  @override
  Widget build(BuildContext context) {
    // listen to login/logout events from firebase
    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snapshot) {
        // show splash spinner while checking session on launch
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // logged in -> go to dashboard / home
        if (snapshot.hasData) {
          return const HomeScreen();
        }

        // logged out -> show sign-in screen
        return const LoginScreen();
      },
    );
  }
}
