import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// [ v a l i d a t o r s ]
class AuthValidators {
  // make sure name is not empty or just spaces
  static String? requiredName(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Full name is required' : null;

  // basic email regex pattern
  static String? email(String? v) {
    final value = v?.trim() ?? '';

    if (value.isEmpty) return 'Email is required';

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
      return 'Enter a valid email';
    }

    return null;
  }

  // enforce min 8 chars for new password
  static String? newPassword(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'Password must have atleast 8 characters';
    return null;
  }

  // checks if login is non-empty
  static String? existingPassword(String? v) =>
      (v == null || v.isEmpty) ? 'Password is required' : null;
}

// [ p a g e   s c r e e n ]

// --------------------------------------------------------------- PAGE SHELL
// bg photo + default color + scrollable center
class AuthScaffold extends StatelessWidget {
  final Widget child;

  const AuthScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8EF), // fallback if the image fails
      body: Stack(
        fit: StackFit.expand,
        children: [
          // background photo (bottom layer)
          Image.asset(
            'assets/images/auth_bg.jpg',
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),

          // soft wash so form stays readable over photo
          // (lower the alpha for a clearer photo, or delete this line)
          Container(color: const Color(0xFFFFF8EF).withValues(alpha: 0.6)),

          // centered scrollable form area
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 24,
                ),
                // cap width so layout doesn't look stretched on tablets / web
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
// app logo + serif title
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset(
          'assets/images/logo.png',
          height: 80,
          errorBuilder: (_, _, _) => const SizedBox(height: 80),
        ),
        const SizedBox(height: 6),
        Text(
          'IsKO-LATER',
          style: GoogleFonts.dmSerifDisplay(
            fontSize: 28,
            color: const Color(0xFF4A3427),
          ),
        ),
      ],
    );
  }
}

// [ t e x t f i e l d ]
// custom input field with built-in password visibility toggle
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
  // password visibility toggle state
  bool _hidden = true;

  // reusable rounded border style
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
        // input field label
        Text(
          widget.label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Color(0xFF4A3427),
          ),
        ),
        const SizedBox(height: 6),

        // input box
        TextFormField(
          controller: widget.controller,
          enabled: widget.enabled,
          // hidden only for password fields while the eye is "off"
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
            focusedBorder: _border(const Color(0xFF4A3427), width: 1.5),
            errorBorder: _border(const Color(0xFFB3261E)),
            focusedErrorBorder: _border(const Color(0xFFB3261E), width: 1.5),

            // show eye icon only if it is a password field
            suffixIcon: widget.isPassword
                ? IconButton(
                    tooltip: _hidden ? 'Show password' : 'Hide password',
                    icon: Icon(
                      _hidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: const Color(0xFF4A3427),
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

// [ p r i m a r y   b u t t o n]
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
          backgroundColor: const Color(0xFF4A3427),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF4A3427)
              .withValues(alpha: 0.6),
          disabledForegroundColor: Colors.white,
          shape: const StadiumBorder(),
        ),

        //show spinner when submitting, else show button label
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
// tinted red banner for firebase auth / validation errors
class AuthErrorBanner extends StatelessWidget {
  final String? message;

  const AuthErrorBanner({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();

    return Semantics(
      liveRegion: true, // announce to screen readers when error appears
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFB3261E).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFB3261E).withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFB3261E), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message!,
                style: const TextStyle(color: Color(0xFFB3261E), fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// [ s w i t c h  s c r e e n]
// redirects between login and signup flows
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
        Text(prompt, style: const TextStyle(color: Color(0xFF4A3427))),
        TextButton(
          onPressed: onTap,
          child: Text(
            action,
            style: const TextStyle(
              color: Color(0xFF6B7F5E),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
