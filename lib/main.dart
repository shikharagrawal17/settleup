import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'providers/app_state.dart';
import 'screens/app_shell.dart';
import 'screens/firebase_setup_screen.dart';
import 'widgets/app_shell_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BharatDuesApp());
}

class BharatDuesApp extends StatelessWidget {
  const BharatDuesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FirebaseApp>(
      future: Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ),
      builder: (context, snapshot) {
        return MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => AppState(),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Bharat Dues',
            theme: _buildTheme(),
            home: _buildHome(snapshot),
          ),
        );
      },
    );
  }

  Widget _buildHome(AsyncSnapshot<FirebaseApp> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const _LaunchScreen();
    }

    if (snapshot.hasError) {
      return FirebaseSetupScreen(error: snapshot.error?.toString());
    }

    return const AppShell();
  }

  ThemeData _buildTheme() {
    const primaryBlue = Color(0xFF00B9F1);
    const darkBlue = Color(0xFF002E6E);
    const background = Color(0xFFF5F7FA);
    const card = Colors.white;

    final base = ThemeData.light(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: background,
      cardColor: card,
      splashFactory: InkSparkle.splashFactory,
      colorScheme: base.colorScheme.copyWith(
        primary: primaryBlue,
        secondary: darkBlue,
        surface: card,
      ),
      textTheme: base.textTheme.copyWith(
        displaySmall: const TextStyle(
          fontSize: 36,
          height: 1.1,
          fontWeight: FontWeight.w700,
          color: darkBlue,
          letterSpacing: -1.2,
        ),
        headlineSmall: const TextStyle(
          fontSize: 24,
          height: 1.2,
          fontWeight: FontWeight.w700,
          color: darkBlue,
          letterSpacing: -0.5,
        ),
        titleLarge: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: darkBlue,
        ),
        bodyLarge: const TextStyle(
          fontSize: 15,
          height: 1.6,
          color: Colors.black87,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: darkBlue),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: darkBlue,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: const TextStyle(color: Colors.black45, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryBlue, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          backgroundColor: Colors.transparent,
          foregroundColor: darkBlue,
          side: const BorderSide(color: primaryBlue),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          backgroundColor: Colors.black.withValues(alpha: 0.05),
          foregroundColor: darkBlue,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        selectedColor: primaryBlue,
        secondarySelectedColor: primaryBlue,
        labelStyle: const TextStyle(fontSize: 12),
        backgroundColor: Colors.black.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
      ),
    );
  }
}

class _LaunchScreen extends StatelessWidget {
  const _LaunchScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: AppBackdrop(
        child: Center(
          child: SizedBox(
            width: 42,
            height: 42,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      ),
    );
  }
}
