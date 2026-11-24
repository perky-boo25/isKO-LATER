import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../utils/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/auth_widgets.dart';

// [ f o r g o t   p a s s w o r d   s c r e e n ]
// handles email-based password recovery via firebase auth link
class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  late final TextEditingController _emailController;

  bool _isLoading = false;
  bool _sent = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _authService.sendPasswordReset(_emailController.text);
      if (mounted) setState(() => _sent = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Something went wrong. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(child: _sent ? _buildSent(context) : _buildForm(context));
  }

  Widget _buildForm(BuildContext context) {
    final compact = Responsive.isCompactHeight(context);

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: AuthHeader()),
          SizedBox(height: compact ? 28 : 44),
          Center(
            child: Text(
              'Reset your password',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: compact ? 24 : 28,
                fontWeight: FontWeight.w600,
                color: AppColors.espresso,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              "Enter your registered email address and we'll send you a link to reset your password.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.brown.shade400),
            ),
          ),
          const SizedBox(height: 24),
          AuthTextField(
            label: 'Email',
            hint: 'yourname@example.com',
            controller: _emailController,
            enabled: !_isLoading,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            onSubmitted: (_) => _submit(),
            validator: AuthValidators.email,
          ),
          const SizedBox(height: 16),
          AuthErrorBanner(message: _errorMessage),
          AuthPrimaryButton(
            label: 'Send reset link',
            isLoading: _isLoading,
            onPressed: _submit,
          ),
          const SizedBox(height: 20),
          Center(
            child: AuthSwitchLink(
              prompt: 'Remembered it?',
              action: 'Log in',
              onTap: _isLoading ? null : () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  // scales the envelope illustration to screen height so buttons never get pushed off-screen
  Widget _buildSent(BuildContext context) {
    final compact = Responsive.isCompactHeight(context);
    final imageHeight = Responsive.illustrationHeight(
      context,
      ratio: 0.24,
      min: 120.0,
      max: 230.0,
    );

    return Column(
      children: [
        const AuthHeader(),
        SizedBox(height: compact ? 24 : 40),
        Image.asset(
          'assets/images/ec.png',
          height: imageHeight,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const SizedBox(height: 65, width: 65),
        ),
        const SizedBox(height: 18),
        Text(
          'Check your inbox',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: compact ? 24 : 28,
            fontWeight: FontWeight.w600,
            color: AppColors.espresso,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Check your inbox! If ${_emailController.text.trim()} is registered, your reset link is on its way. Be sure to check your spam folder before it expires.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.brown.shade400),
        ),
        SizedBox(height: compact ? 22 : 32),
        AuthPrimaryButton(
          label: 'Back to login',
          isLoading: false,
          onPressed: () => Navigator.of(context).pop(),
        ),
        TextButton(
          onPressed: () => setState(() => _sent = false),
          child: const Text(
            'Use a different email',
            style: TextStyle(color: AppColors.oliveAccent),
          ),
        ),
      ],
    );
  }
}
