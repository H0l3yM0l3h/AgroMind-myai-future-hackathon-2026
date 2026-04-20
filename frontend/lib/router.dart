import 'package:go_router/go_router.dart';

import 'screens/landing_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/project_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const LandingScreen(),
    ),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardScreen(),
    ),
    GoRoute(
      path: '/project/:id',
      builder: (context, state) {
        final projectId = state.pathParameters['id']!;
        return ProjectScreen(projectId: projectId);
      },
    ),
  ],
);
