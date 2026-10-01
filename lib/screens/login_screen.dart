import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../widgets/auth_widgets.dart';
import 'register_screen.dart';

// [ l o g i n   s c r e e n ]
// handles user sign in with email & password
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  //form state + auth logic handler
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  //text controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // page ui states
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    // clean up controllers on exit
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // [ s u b m i t ]
  //validate inputs -> sign in via firebase
  Future<void> _submit() async {
    //dismiss onscreen keyboard & clear old errors
    FocusScope.of(context).unfocus();
    setState(() => _errorMessage = null);

    // stop if client validation fails
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // attempt firebase login
      await _authService.login(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } on AuthException catch (e) {
      // display mapped firebase error
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      // fallback generic error
      if (mounted) {
        setState(
          () => _errorMessage = 'Something went wrong. Please try again',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // logo header
              const Center(child: AuthHeader()),
              const SizedBox(height: 32),

              // page title & subtitle
              Text(
                'Welcome back',
                style: GoogleFonts.dmSerifDisplay(
                  fontSize: 28,
                  color: Color(0xFF4A3427),
                ),
              ),

              const SizedBox(height: 4),

              Text(
                'Stay on top of what matters',
                style: TextStyle(color: Color(0xFF4A3427)),
              ),

              const SizedBox(height: 24),

              // (1) email field
              AuthTextField(
                label: 'Email',
                hint: 'yourname@gmail.com',
                controller: _emailController,
                enabled: !_isLoading,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                validator: AuthValidators.email,
              ),

              const SizedBox(height: 16),

              // (2) password field with hide and show toggle
              AuthTextField(
                label: 'Password',
                hint: 'Enter your Password',
                controller: _passwordController,
                isPassword: true,
                enabled: !_isLoading,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _submit(),
                validator: AuthValidators.existingPassword,
              ),

              //TODO: Forgot Password UI here
              const SizedBox(height: 8),

              // inline error banner
              AuthErrorBanner(message: _errorMessage),

              //login submission button
              AuthPrimaryButton(
                label: 'Log in',
                isLoading: _isLoading,
                onPressed: _submit,
              ),

              const SizedBox(height: 20),

              // link to redirect to registration screen
              AuthSwitchLink(
                prompt: 'New here?',
                action: 'Sign up',
                onTap: _isLoading
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const RegisterScreen(),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
