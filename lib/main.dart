import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'firebase_options.dart';
import 'screens/auth_gate.dart';

// entry point - setting up firebase before the app runs
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // connection to firebase backend
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const IskoLaterApp());
}

// main widget - app wide theme and starting screen
class IskoLaterApp extends StatelessWidget {
  const IskoLaterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'IsKO-LATER',
      theme: ThemeData(
        colorSchemeSeed: Colors.brown,
        useMaterial3: true,
        textTheme: GoogleFonts.dmSansTextTheme(),
      ),

      // clamp extreme OS font scaling so text never overflows cards or buttons
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final scaler = mq.textScaler.clamp(
          minScaleFactor: 0.85,
          maxScaleFactor: 1.20,
        );
        return MediaQuery(
          data: mq.copyWith(textScaler: scaler),
          child: child ?? const SizedBox.shrink(),
        );
      },

      // first screen to launch
      home: const AuthGate(),
    );
  }
}
