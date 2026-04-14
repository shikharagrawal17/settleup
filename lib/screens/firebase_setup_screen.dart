import 'package:flutter/material.dart';

class FirebaseSetupScreen extends StatelessWidget {
  const FirebaseSetupScreen({
    super.key,
    this.error,
  });

  final String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Text(
                'Firebase setup needed',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 16),
              const Text(
                'This build now uses Firebase Auth and Firestore. Run FlutterFire setup for Android and iOS, then reopen the app.',
                style: TextStyle(color: Colors.white70, height: 1.5),
              ),
              const SizedBox(height: 20),
              const SelectableText(
                'flutterfire configure\nflutter pub get\nflutter run',
              ),
              if (error != null) ...[
                const SizedBox(height: 20),
                Text(
                  error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
