// go_router package for declarative URL-based navigation
import 'package:go_router/go_router.dart';

// The three screens that make up the AgroMind app
import 'screens/landing_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/project_screen.dart';

// Global router instance consumed by MaterialApp.router in main.dart
// Defines all 3 routes in the app — no nested routing needed at this scale
final appRouter = GoRouter(
  initialLocation: '/',  // App always starts at the landing screen
  routes: [
    // Route 1: Landing page — hero section, feature grid, CTA button
    GoRoute(
      path: '/',
      builder: (context, state) => const LandingScreen(),
    ),

    // Route 2: Dashboard — project list, create/delete projects
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardScreen(),
    ),

    // Route 3: Project analysis screen — map, AI pipeline, report, chatbot
    // :id is a dynamic path parameter containing the Firestore document UUID
    GoRoute(
      path: '/project/:id',
      builder: (context, state) {
        // Extract the project UUID from the URL path and pass it to the screen
        // The '!' asserts non-null — the param is always present on this route
        final projectId = state.pathParameters['id']!;
        return ProjectScreen(projectId: projectId);
      },
    ),
  ],
);