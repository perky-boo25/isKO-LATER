import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../widgets/auth_widgets.dart';

// [ f o r g o t   p a s s w o r d   s c r e e n ]
// handles email-based password recovery via firebase auth link
// toggles between form submission and confirmation views
class ForgotPasswordScreen extends StatefulWidget {
  // prefill email if forwarded from login screen
  final String initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  // form state + auth logic handler
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  late final TextEditingController _emailController;

  // page ui states
  bool _isLoading = false;
  bool _sent = false; // switches form to check-inbox confirmation
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // initialize field with passed email or empty string
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    // clean up controller on exit
    _emailController.dispose();
    super.dispose();
  }

  // [ s u b m i t ]
  // validate email -> request reset link via firebase auth
  Future<void> _submit() async {
    // dismiss on-screen keyboard & clear old errors
    FocusScope.of(context).unfocus();
    setState(() => _errorMessage = null);

    // stop if client validation fails
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // send reset email trigger
      await _authService.sendPasswordReset(_emailController.text);
      if (mounted) setState(() => _sent = true);
    } on AuthException catch (e) {
      // display mapped error
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      // fallback generic error
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
    // swap view dynamically based on delivery state
    return AuthScaffold(child: _sent ? _buildSent() : _buildForm());
  }

  // [ f o r m   v i e w ]
  // initial email entry field + submit action
  Widget _buildForm() {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // logo header
          const Center(child: AuthHeader()),
          const SizedBox(height: 50),

          // title & instructional copy
          Center(
            child: Text(
              'Reset your password',
              style: GoogleFonts.poppins(
                fontSize: 28,
                fontWeight: FontWeight(600),
                color: const Color(0xFF4A3427),
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

          // email input field
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

          // inline error banner
          AuthErrorBanner(message: _errorMessage),

          // send link submit button
          AuthPrimaryButton(
            label: 'Send reset link',
            isLoading: _isLoading,
            onPressed: _submit,
          ),

          const SizedBox(height: 20),

          Center(
            child:
                // link to return to sign in
                AuthSwitchLink(
                  prompt: 'Remembered it?',
                  action: 'Log in',
                  onTap: _isLoading ? null : () => Navigator.of(context).pop(),
                ),
          ),
        ],
      ),
    );
  }

  // [ s e n t   v i e w ]
  // neutral success screen preventing account enumeration attacks
  Widget _buildSent() {
    return Column(
      children: [
        // logo header
        const AuthHeader(),
        const SizedBox(height: 50),

        // success mail icon
        Image.asset(
          'assets/images/ec.png', // Replace with your image asset path
          height: 250,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const SizedBox(height: 65, width: 65),
        ),
        const SizedBox(height: 20),

        // confirmation heading
        Text(
          'Check your inbox',
          style: GoogleFonts.poppins(
            fontSize: 28,
            fontWeight: FontWeight(600),
            color: const Color(0xFF4A3427),
          ),
        ),
        const SizedBox(height: 8),

        // neutral feedback description
        Text(
          'Check your inbox! If ${_emailController.text.trim()} is registered, your reset link is on its way. Be sure to check your spam folder before it expires.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.brown.shade400),
        ),
        const SizedBox(height: 35),

        // return to login flow
        AuthPrimaryButton(
          label: 'Back to login',
          isLoading: false,
          onPressed: () => Navigator.of(context).pop(),
        ),

        // retry or correct typed address
        TextButton(
          onPressed: () => setState(() => _sent = false),
          child: const Text(
            'Use a different email',
            style: TextStyle(color: Color(0xFF6B7F5E)),
          ),
        ),
      ],
    );
  }
}
