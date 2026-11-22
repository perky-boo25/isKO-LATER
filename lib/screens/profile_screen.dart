import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../utils/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/app_shared.dart';
import '../widgets/auth_widgets.dart' show AuthValidators;

// [ p r o f i l e   s c r e e n ]
// landing page post-login: account details (editable) & sign-out
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  // controllers for the editable username and email fields
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;

  // UI state toggles
  bool _editingName = false;
  bool _editingEmail = false;
  bool _saving = false;

  // email-change verification state
  String? _pendingEmail; // new email we're waiting to be verified
  String? _pendingUid;
  Timer? _pollTimer;
  bool _checking = false; // stops overlapping checks
  bool _loggingOut = false; // pauses checks during a manual logout

  @override
  void initState() {
    super.initState();
    // grab current user data on load
    final user = AuthService().currentUser;
    _nameCtrl = TextEditingController(text: user?.displayName?.trim() ?? '');
    _emailCtrl = TextEditingController(text: user?.email ?? '');

    // rebuild on typing so "Verify changes" enables/disables live
    _nameCtrl.addListener(() => setState(() {}));
    _emailCtrl.addListener(() => setState(() {}));

    AuthService().syncProfileToFirestore(); // fire-and-forget

    // lets us re-check the moment the user comes back from their mail app
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  // back from the mail app: check right away instead of waiting for the timer
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkVerification();
  }

  // [ s a v e   l o g i c ]
  // delegates data updating to AuthService and handles UI feedback
  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final user = AuthService().currentUser;
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();

    if (name.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Username can\'t be empty.')),
      );
      return;
    }

    final emailChanged =
        email.toLowerCase() != (user?.email ?? '').toLowerCase();

    // changing the email requires the current password (re-authentication)
    String? password;
    if (emailChanged) {
      final formatError = AuthValidators.email(email);
      if (formatError != null) {
        messenger.showSnackBar(SnackBar(content: Text(formatError)));
        return;
      }
      password = await showDialog<String>(
        context: context,
        builder: (_) => const _ReauthDialog(),
      );
      if (password == null || !mounted) return; // cancelled
    }

    setState(() => _saving = true);

    try {
      // pass data to service layer
      final message = await AuthService().updateProfile(
        newName: name,
        newEmail: email,
        currentPassword: password,
      );

      // close editing mode on success
      if (mounted) {
        setState(() {
          _editingName = false;
          _editingEmail = false;
          // email only changes after the link is tapped, so show the current one
          _emailCtrl.text = AuthService().currentUser?.email ?? '';
        });
        // link sent: start waiting for the user to verify it
        if (emailChanged && user != null) {
          _startWaiting(uid: user.uid, newEmail: email);
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } on AuthException catch (e) {
      // show mapped error from service (wrong password, email already used...)
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
        // revert email field if it failed
        _emailCtrl.text = AuthService().currentUser?.email ?? '';
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // [ w a i t   f o r   v e r i f i c a t i o n ]
  void _startWaiting({required String uid, required String newEmail}) {
    _pollTimer?.cancel();
    setState(() {
      _pendingEmail = newEmail;
      _pendingUid = uid;
    });
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _checkVerification(),
    );
  }

  void _stopWaiting() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (mounted) {
      setState(() {
        _pendingEmail = null;
        _pendingUid = null;
      });
    }
  }

  Future<void> _checkVerification() async {
    final email = _pendingEmail;
    final uid = _pendingUid;
    if (email == null || uid == null || _checking || _loggingOut) return;

    _checking = true;
    try {
      final verified = await AuthService().completeEmailChangeIfVerified(
        uid: uid,
        newEmail: email,
      );
      if (verified && mounted) {
        _stopWaiting();
        await _showVerifiedDialog(email);
      }
    } finally {
      _checking = false;
    }
  }

  // success dialog -> sign out -> back to login with the new email filled in
  Future<void> _showVerifiedDialog(String newEmail) async {
    final navigator = Navigator.of(context); // capture before the awaits

    await showDialog<void>(
      context: context,
      barrierDismissible: false, // must acknowledge; no skipping the logout
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: AppColors.creamSurface,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: AppColors.espresso.withValues(alpha: 0.15)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: AppColors.oliveAccent.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.verified_outlined,
                      color: Color(0xFF6B7F4E),
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Email verified',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSerifDisplay(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.espresso,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your email is now $newEmail.\n\n'
                    'For your security, please log in again with your new email.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: AppColors.espresso.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.espresso,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text(
                      'Go to login',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // set BEFORE signing out so LoginScreen listener fills the field immediately
    loginEmailPrefill.value = newEmail;
    try {
      await AuthService().logout(); // harmless if firebase already did it
    } catch (_) {}
    navigator.popUntil((route) => route.isFirst); // reveal the login screen
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.profileSurface,
      body: SafeArea(
        child: StreamBuilder<User?>(
          stream: AuthService().userChanges,
          initialData: AuthService().currentUser,
          builder: (context, snapshot) {
            final user = snapshot.data;
            if (user == null) return const SizedBox.shrink();

            final displayName = user.displayName?.trim() ?? '';
            final email = user.email ?? '';

            // check if the user has typed anything new
            final dirty =
                _nameCtrl.text.trim() != displayName ||
                _emailCtrl.text.trim() != email;

            return Column(
              children: [
                const _HeaderBanner(),

                Expanded(
                  child: Responsive.constrainWidth(
                    context,
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        Responsive.horizontalPadding(context),
                        Responsive.isCompactHeight(context) ? 14 : 20,
                        Responsive.horizontalPadding(context),
                        24,
                      ),
                      children: [
                        _SoftCard(
                          padding: EdgeInsets.all(
                            Responsive.isNarrow(context) ? 16 : 20,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: Responsive.isCompactHeight(context)
                                    ? 68
                                    : 84,
                                height: Responsive.isCompactHeight(context)
                                    ? 68
                                    : 84,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF2EAE3),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.person_outline,
                                  size: Responsive.isCompactHeight(context)
                                      ? 34
                                      : 42,
                                  color: AppColors.espresso,
                                ),
                              ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName.isEmpty
                                        ? 'No username'
                                        : displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: AppColors.espresso.withValues(
                                        alpha: 0.65,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      Text(
                        'Account details',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 15),

                      _EditableTile(
                        label: 'Username',
                        controller: _nameCtrl,
                        editing: _editingName,
                        keyboardType: TextInputType.name,
                        onToggle: () =>
                            setState(() => _editingName = !_editingName),
                      ),
                      const SizedBox(height: 12),
                      _EditableTile(
                        label: 'Email',
                        controller: _emailCtrl,
                        editing: _editingEmail,
                        keyboardType: TextInputType.emailAddress,
                        onToggle: () =>
                            setState(() => _editingEmail = !_editingEmail),
                      ),

                      const SizedBox(height: 16),

                      Row(
                        children: [
                          const Icon(
                            Icons.verified_user_outlined,
                            color: Color(0xFF6B7F4E),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Email changes require verification.',
                              style: GoogleFonts.poppins(
                                fontSize: 12.5,
                                color: AppColors.espresso.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // shown while we wait for the user to tap the emailed link
                      if (_pendingEmail != null) ...[
                        const SizedBox(height: 16),
                        _SoftCard(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF6B7F4E),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Waiting for you to verify $_pendingEmail. '
                                  'Open the link we emailed, then come back here.',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12.5,
                                    color: AppColors.espresso.withValues(
                                      alpha: 0.8,
                                    ),
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _stopWaiting,
                                child: const Text('Stop'),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      FilledButton(
                        onPressed: (dirty && !_saving) ? _save : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.espresso,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.espresso
                              .withValues(alpha: 0.35),
                          disabledForegroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(56),
                          shape: const StadiumBorder(),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Verify changes',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 17,
                                ),
                              ),
                      ),
                      const SizedBox(height: 12),

                      // [ l o g o u t   a c t i o n ]
                      FilledButton.icon(
                        onPressed: () async {
                          // so a manual logout isn't mistaken for a verified email
                          _loggingOut = true;
                          await logoutAndReturnToRoot(context);
                          _loggingOut = false;
                        },
                        icon: const Icon(Icons.logout),
                        label: Text(
                          'Log out',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w500,
                            fontSize: 17,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.logoutAmber,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(56),
                          shape: const StadiumBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentTab: AppTab.profile),
    );
  }
}

class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner();

  @override
  Widget build(BuildContext context) {
    final compact = Responsive.isCompactHeight(context);
    return Container(
      width: double.infinity,
      padding: Responsive.headerPadding(context),
      color: AppColors.creamHeader,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Image.asset(
          'assets/images/app_title.png',
          height: compact ? 36 : 45,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _SoftCard({required this.child, required this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEFE6DD)),
        boxShadow: [
          BoxShadow(
            color: AppColors.espresso.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _EditableTile extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool editing;
  final TextInputType keyboardType;
  final VoidCallback onToggle;

  const _EditableTile({
    required this.label,
    required this.controller,
    required this.editing,
    required this.keyboardType,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final valueStyle = GoogleFonts.poppins(
      fontSize: 17,
      fontWeight: FontWeight.w500,
      color: Colors.black,
    );

    return _SoftCard(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: AppColors.espresso.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 2),
                if (editing)
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: keyboardType,
                    style: valueStyle,
                    cursorColor: AppColors.espresso,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 6),
                      border: InputBorder.none,
                    ),
                  )
                else
                  Text(
                    controller.text.isEmpty ? '—' : controller.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: valueStyle,
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: editing ? 'Done editing $label' : 'Edit $label',
            onPressed: onToggle,
            icon: Icon(editing ? Icons.check : Icons.edit_outlined, size: 20),
            color: const Color(0xFF6B7F4E),
            splashColor: const Color(0xFF6B7F4E).withValues(alpha: 0.2),
            highlightColor: const Color(0xFF6B7F4E).withValues(alpha: 0.1),
          ),
        ],
      ),
    );
  }
}

// asks for the CURRENT password before an email change (re-authentication)
// returns the typed password, or null if cancelled
class _ReauthDialog extends StatefulWidget {
  const _ReauthDialog();

  @override
  State<_ReauthDialog> createState() => _ReauthDialogState();
}

class _ReauthDialogState extends State<_ReauthDialog> {
  final _ctrl = TextEditingController();
  bool _hidden = true;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_ctrl.text.isEmpty) return;
    Navigator.pop(context, _ctrl.text);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.creamSurface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: AppColors.espresso.withValues(alpha: 0.15)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppColors.espresso.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: AppColors.espresso,
                  size: 26,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Confirm it\u2019s you',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSerifDisplay(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.espresso,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your current password to change your email.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppColors.espresso.withValues(alpha: 0.78),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _ctrl,
                obscureText: _hidden,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'Current password',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.brown.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.brown.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: AppColors.espresso,
                      width: 1.5,
                    ),
                  ),
                  suffixIcon: IconButton(
                    tooltip: _hidden ? 'Show password' : 'Hide password',
                    icon: Icon(
                      _hidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppColors.espresso,
                    ),
                    onPressed: () => setState(() => _hidden = !_hidden),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.espresso,
                          side: BorderSide(
                            color: AppColors.espresso.withValues(alpha: 0.35),
                          ),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: FilledButton(
                        onPressed: _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.espresso,
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                        ),
                        child: const Text(
                          'Continue',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
