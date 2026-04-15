import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';
import 'sign_in_screen.dart';
import '../models/user_profile.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();

    return StreamBuilder<User?>(
      stream: appState.authStateChanges,
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState != ConnectionState.active) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = authSnapshot.data;
        if (user == null) {
          return const SignInScreen();
        }

        // If authenticated, also verify the Firestore profile exists.
        return StreamBuilder<UserProfile?>(
          stream: appState.profileStream(user.uid),
          builder: (context, profileSnapshot) {
            // Handle error or missing data when connection is established
            if (profileSnapshot.connectionState == ConnectionState.active ||
                profileSnapshot.connectionState == ConnectionState.done) {
              
              if (profileSnapshot.hasError || profileSnapshot.data == null) {
                // User is authenticated but Firestore profile is missing or errored
                // This forces immediate re-onboarding if database is cleared.
                return OnboardingScreen(user: user);
              }

              return HomeScreen(user: user, profile: profileSnapshot.data!);
            }

            // Waiting for first snapshot
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          },
        );
      },
    );
  }
}
