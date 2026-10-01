import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../widgets/auth_widgets.dart';

// [ r e g i s t e r   s c r e e n ]
// handles new user sign up + firestore doc creation
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  //form state + auth logic handler
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  // text controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  // page UI states
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    //clean up constrollers on exit
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // [ s u b m i t]
  // validates fields -> register via firebase -> pop back to root
  Future<void> _submit() async {
    // dismiss onscreen keyboard & clear old errors
    FocusScope.of(context).unfocus();
    setState(() => _errorMessage = null);

    // stop if client validation fails
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // (1) send payload to auth service
      await _authService.register(
        userName: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
      );

      // (2) navigate back to auth gate on success
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (e) {
      // display mapped firebase error
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
    return PopScope(
      // lock back navigation while request is in flight
      canPop: !_isLoading,
      child: AuthScaffold(
        child: Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // logo header
                const Center(child: AuthHeader()),
                const SizedBox(height: 32),

                // page title
                Text(
                  'Create you account',
                  style: GoogleFonts.dmSerifDisplay(
                    fontSize: 28,
                    color: Color(0xFF4A3427),
                  ),
                ),

                const SizedBox(height: 24),

                // (1) full name field
                AuthTextField(
                  label: 'Full name',
                  hint: 'Juan de la Cruz',
                  controller: _nameController,
                  enabled: !_isLoading,
                  keyboardType: TextInputType.name,
                  autofillHints: const [AutofillHints.name],
                  validator: AuthValidators.requiredName,
                ),

                const SizedBox(height: 16),

                // (2) email field
                AuthTextField(
                  label: 'Email',
                  hint: 'yourname@example.com',
                  controller: _emailController,
                  enabled: !_isLoading,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  validator: AuthValidators.newPassword,
                ),

                const SizedBox(height: 16),

                // (3) password field
                AuthTextField(
                  label: 'Password',
                  hint: 'Must be atleast 8 characters',
                  controller: _passwordController,
                  isPassword: true,
                  enabled: !_isLoading,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: AuthValidators.newPassword,
                ),

                const SizedBox(height: 16),

                // (4) confirm password field
                AuthTextField(
                  label: 'Confirm password',
                  hint: 'Type your password again',
                  controller: _confirmController,
                  isPassword: true,
                  enabled: !_isLoading,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  onSubmitted: (_) => _submit(),
                  validator: (value) => value != _passwordController.text
                      ? 'Password do not match'
                      : null,
                ),

                const SizedBox(height: 24),

                // inline error message banner
                AuthErrorBanner(message: _errorMessage),

                // register submission button
                AuthPrimaryButton(
                  label: 'Create account',
                  isLoading: _isLoading,
                  onPressed: _submit,
                ),

                const SizedBox(height: 20),

                // link back to sign-in screen
                AuthSwitchLink(
                  prompt: 'Already have an account?',
                  action: 'Log in',
                  onTap: _isLoading ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
