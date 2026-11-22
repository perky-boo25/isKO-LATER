import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/app_theme.dart';
import '../utils/responsive.dart';

// [ v a l i d a t o r s ]
class AuthValidators {
  static String? requiredName(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Full name is required' : null;

  static String? email(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Email is required';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
      return 'Enter a valid email';
    }
    return null;
  }

  static String? newPassword(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'Password must have atleast 8 characters';
    return null;
  }

  static String? existingPassword(String? v) =>
      (v == null || v.isEmpty) ? 'Password is required' : null;
}

// [ p a g e   s h e l l ]
// background photo + soft wash + centered scrollable form area
class AuthScaffold extends StatelessWidget {
  final Widget child;

  const AuthScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final compact = Responsive.isCompactHeight(context);
    final hPad = Responsive.isNarrow(context) ? 20.0 : 28.0;

    return Scaffold(
      backgroundColor: AppColors.creamSurface,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/auth_bg.jpg',
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
          Container(color: AppColors.creamSurface.withValues(alpha: 0.6)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: hPad,
                  vertical: compact ? 16 : 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// [ h e a d e r ]
// app logo + tagline scaled to screen height
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final logoHeight = Responsive.illustrationHeight(
      context,
      ratio: 0.12,
      min: 64.0,
      max: 100.0,
    );

    return Column(
      children: [
        Image.asset(
          'assets/images/app_title.png',
          height: logoHeight,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const SizedBox(height: 32),
        ),
        Text(
          'mastering the art of mamaya na',
          textAlign: TextAlign.center,
          style: GoogleFonts.specialElite(
            fontSize: Responsive.isNarrow(context) ? 14 : 16,
          ),
        ),
      ],
    );
  }
}

// [ t e x t f i e l d ]
// input field with built-in password visibility toggle
class AuthTextField extends StatefulWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool isPassword;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final String? Function(String?)? validator;
  final void Function(String)? onSubmitted;

  const AuthTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    this.isPassword = false,
    this.enabled = true,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.validator,
    this.onSubmitted,
  });

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  bool _hidden = true;

  OutlineInputBorder _border(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: AppColors.espresso,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: widget.controller,
          enabled: widget.enabled,
          obscureText: widget.isPassword && _hidden,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          autofillHints: widget.autofillHints,
          validator: widget.validator,
          onFieldSubmitted: widget.onSubmitted,
          decoration: InputDecoration(
            hintText: widget.hint,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.7),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: _border(Colors.brown.shade200),
            enabledBorder: _border(Colors.brown.shade200),
            focusedBorder: _border(AppColors.espresso, width: 1.5),
            errorBorder: _border(AppColors.errorRed),
            focusedErrorBorder: _border(AppColors.errorRed, width: 1.5),
            suffixIcon: widget.isPassword
                ? IconButton(
                    tooltip: _hidden ? 'Show password' : 'Hide password',
                    icon: Icon(
                      _hidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppColors.espresso,
                    ),
                    onPressed: () => setState(() => _hidden = !_hidden),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

// [ p r i m a r y   b u t t o n ]
// pill-shaped brown button with built-in loading spinner
class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.espresso,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.espresso.withValues(alpha: 0.6),
          disabledForegroundColor: Colors.white,
          shape: const StadiumBorder(),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
      ),
    );
  }
}

// [ e r r o r   b a n n e r ]
class AuthErrorBanner extends StatelessWidget {
  final String? message;

  const AuthErrorBanner({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.errorRed.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.errorRed.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.errorRed,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message!,
                style: const TextStyle(color: AppColors.errorRed, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// [ s w i t c h   s c r e e n ]
class AuthSwitchLink extends StatelessWidget {
  final String prompt;
  final String action;
  final VoidCallback? onTap;

  const AuthSwitchLink({
    super.key,
    required this.prompt,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(prompt, style: const TextStyle(color: AppColors.espresso)),
        TextButton(
          onPressed: onTap,
          child: Text(
            action,
            style: const TextStyle(
              color: AppColors.oliveAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
