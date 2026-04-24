// Firebase core package required for initialising Firebase before app launch
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

// Riverpod for app-wide state management — ProviderScope must wrap the entire app
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Firebase configuration generated from .env via String.fromEnvironment() at build time
import 'firebase_options.dart';

// App-wide dark theme definition with AgroMind design tokens
import 'theme.dart';

// go_router configuration defining the 3 app routes: /, /dashboard, /project/:id
import 'router.dart';

Future<void> main() async {
  // Ensure Flutter engine is fully initialised before calling any platform plugins
  // Required when calling native code (Firebase) before runApp()
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Firebase using platform-specific config values injected at build time
  // via --dart-define-from-file=.env (keys are never hardcoded in source)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    // ProviderScope is required by Riverpod — must wrap the entire widget tree
    // so all providers are accessible from any widget in the app
    const ProviderScope(
      child: AgroMindApp(),
    ),
  );
}

// Root widget of the AgroMind application.
// Stateless because all app state is managed by Riverpod providers.
class AgroMindApp extends StatelessWidget {
  const AgroMindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'AgroMind',
      debugShowCheckedModeBanner: false, // Hide the debug banner in all builds
      theme: AppTheme.darkTheme,         // Apply the dark glassmorphic theme globally
      routerConfig: appRouter,           // Delegate all routing to go_router
    );
  }
}