import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../widgets/app_shell_widgets.dart';

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'UPI-first group settlement',
                    style: TextStyle(
                      color: kAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Split bills,\nsettle beautifully.',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 16),
                Text(
                  'A cleaner group expense app for India. Bring in contacts, save your UPI, and reduce messy back-and-forth payments to the smallest useful set of transfers.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white70,
                      ),
                ),
                const SizedBox(height: 28),
                const AppSurface(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: MetricPill(
                              label: 'Groups',
                              value: 'Shared',
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: MetricPill(
                              label: 'Payments',
                              value: 'UPI ready',
                              highlight: true,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: MetricPill(
                              label: 'Contacts',
                              value: 'Import fast',
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: MetricPill(
                              label: 'Transfers',
                              value: 'Simplified',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: appState.isSigningIn ? null : appState.signInWithGoogle,
                    icon: appState.isSigningIn
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: Text(appState.isSigningIn ? 'Signing In...' : 'Continue with Google'),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Your groups and UPI settings stay tied to your account.',
                  style: TextStyle(color: Colors.white54),
                ),
                if (appState.authError != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    appState.authError!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
