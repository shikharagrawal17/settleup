import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../widgets/app_shell_widgets.dart';

enum AuthView { initial, phone, otp }

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  AuthView _view = AuthView.initial;
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  String _phoneNumber = '';

  void _verifyPhone(AppState appState) {
    if (_phoneController.text.isEmpty) return;
    _phoneNumber = _phoneController.text.trim();
    
    appState.verifyPhone(
      phoneNumber: _phoneNumber,
      codeSent: (vid, token) {
        setState(() => _view = AuthView.otp);
      },
      verificationFailed: (err) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      },
    );
  }

  void _submitOtp(AppState appState) {
    if (_otpController.text.length < 6) return;
    appState.signInWithOtp(_otpController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 60),
                  Center(child: Image.asset('assets/images/logo.png', height: 100)),
                  const SizedBox(height: 40),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: kPrimaryBlue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'UPI-first group settlement',
                        style: TextStyle(
                          color: kPrimaryBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _view == AuthView.initial 
                      ? 'Split bills,\nsettle beautifully.' 
                      : _view == AuthView.phone ? 'Enter your\nphone number' : 'Verify your\nnumber',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 16),
                  if (_view == AuthView.initial)
                    Text(
                      'A cleaner group expense app for India. Bring in contacts, save your UPI, and solve the math automatically.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Colors.black54,
                          ),
                    ),
                  if (_view == AuthView.otp)
                    Text(
                      'Enter the 6-digit code sent to $_phoneNumber',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  const SizedBox(height: 32),
                  
                  if (_view == AuthView.initial) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: appState.isSigningIn ? null : appState.signInWithGoogle,
                        icon: appState.isSigningIn
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.login),
                        label: Text(appState.isSigningIn ? 'Signing In...' : 'Continue with Google'),
                      ),
                    ),
                    /* 
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _view = AuthView.phone),
                        icon: const Icon(Icons.phone_android),
                        label: const Text('Sign in with Phone'),
                      ),
                    ),
                    */
                  ] else if (_view == AuthView.phone) ...[
                    AppSurface(
                      child: TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))],
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Mobile Number',
                          hintText: '+91...',
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: appState.isSigningIn ? null : () => _verifyPhone(appState),
                        child: const Text('Send OTP'),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _view = AuthView.initial),
                      child: const Text('Back to options', style: TextStyle(color: Colors.black38)),
                    ),
                  ] else if (_view == AuthView.otp) ...[
                    AppSurface(
                      child: TextField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        autofocus: true,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: 'Verification Code',
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: appState.isSigningIn ? null : () => _submitOtp(appState),
                        child: appState.isSigningIn 
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Text('Verify & Login'),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _view = AuthView.phone),
                      child: const Text('Retry number', style: TextStyle(color: Colors.black38)),
                    ),
                  ],

                  if (appState.authError != null) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              appState.authError!,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
