import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../utils/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/auth_widgets.dart';

// [ r e g i s t e r   s c r e e n ]
// handles new user sign up and Firestore profile doc creation
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _authService.register(
        userName: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
      );

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
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
    final compact = Responsive.isCompactHeight(context);

    return PopScope(
      canPop: !_isLoading,
      child: AuthScaffold(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: AuthHeader()),
                SizedBox(height: compact ? 20 : 32),

                Center(
                  child: Text(
                    'Create an account',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: compact ? 24 : 28,
                      fontWeight: FontWeight.w700,
                      color: AppColors.espresso,
                    ),
                  ),
                ),
                SizedBox(height: compact ? 18 : 24),

                AuthTextField(
                  label: 'Username',
                  hint: 'Enter your name',
                  controller: _nameController,
                  enabled: !_isLoading,
                  keyboardType: TextInputType.name,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  validator: AuthValidators.requiredName,
                ),
                const SizedBox(height: 16),

                AuthTextField(
                  label: 'Email',
                  hint: 'Enter your email',
                  controller: _emailController,
                  enabled: !_isLoading,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  validator: AuthValidators.email,
                ),
                const SizedBox(height: 16),

                AuthTextField(
                  label: 'Password',
                  hint: 'Must be at least 8 characters',
                  controller: _passwordController,
                  isPassword: true,
                  enabled: !_isLoading,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: AuthValidators.newPassword,
                ),
                const SizedBox(height: 16),

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
                      ? 'Passwords do not match'
                      : null,
                ),
                const SizedBox(height: 24),

                AuthErrorBanner(message: _errorMessage),

                AuthPrimaryButton(
                  label: 'Create account',
                  isLoading: _isLoading,
                  onPressed: _submit,
                ),
                const SizedBox(height: 20),

                Center(
                  child: AuthSwitchLink(
                    prompt: 'Already have an account?',
                    action: 'Log in',
                    onTap: _isLoading
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
