import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../models/agent_step.dart';
import '../models/chat_message.dart';
import '../models/lat_lng.dart';
import '../services/api_service.dart';
import '../services/project_service.dart';

// ---------------------------------------------------------------------------
// API Service provider (singleton)
// ---------------------------------------------------------------------------
final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

// ---------------------------------------------------------------------------
// Project Service provider (singleton)
// ---------------------------------------------------------------------------
final projectServiceProvider = Provider<ProjectService>(
  (ref) => ProjectService(),
);

// ---------------------------------------------------------------------------
// Projects state — real-time stream from Firestore
// ---------------------------------------------------------------------------

/// StreamProvider that listens to real-time updates from the
/// `projects` collection in Firestore.
final projectListProvider = StreamProvider<List<Project>>((ref) {
  final service = ref.watch(projectServiceProvider);
  return service.streamProjects();
});

// ---------------------------------------------------------------------------
// Current agent step (per-project, per-analysis tracking)
// ---------------------------------------------------------------------------
final currentAgentStepProvider = StateProvider.family<AgentStep?, String>(
  (ref, projectId) => null,
);

// ---------------------------------------------------------------------------
// Analysis result (per-project markdown from Documentarian)
// ---------------------------------------------------------------------------
final analysisResultProvider = StateProvider.family<String, String>(
  (ref, projectId) => '',
);

// ---------------------------------------------------------------------------
// Latest planting grid (per-project, fresh from analyze response)
// ---------------------------------------------------------------------------
final latestPlantingGridProvider = StateProvider.family<Map<String, dynamic>?, String>(
  (ref, projectId) => null,
);

// ---------------------------------------------------------------------------
// Loading state for chat (per-project)
// ---------------------------------------------------------------------------
final isAnalyzingProvider = StateProvider.family<bool, String>(
  (ref, projectId) => false,
);

// ---------------------------------------------------------------------------
// Geospatial state — AOI (Area of Interest) boundary & computed area
// (per-project)
// ---------------------------------------------------------------------------

/// The list of boundary points drawn on the interactive map.
final aoiPointsProvider = StateProvider.family<List<LatLng>, String>(
  (ref, projectId) => [],
);

/// The computed land area (in hectares) derived from the AOI polygon.
final landAreaProvider = StateProvider.family<double, String>(
  (ref, projectId) => 0.0,
);

// ---------------------------------------------------------------------------
// Chat conversation history (persisted in-memory for the session)
// ---------------------------------------------------------------------------
final chatHistoryProvider = StateProvider<List<ChatMessage>>(
  (ref) => [],
);

// ---------------------------------------------------------------------------
// Per-project chatbot thread (lightweight /api/chat endpoint)
// ---------------------------------------------------------------------------

/// Per-project chat thread (list of {role: 'user'|'assistant', content: String})
final projectChatHistoryProvider =
    StateProvider.family<List<Map<String, String>>, String>(
  (ref, projectId) => [],
);

/// Per-project flag for "chat is waiting for a response"
final isChattingProvider = StateProvider.family<bool, String>(
  (ref, projectId) => false,
);
