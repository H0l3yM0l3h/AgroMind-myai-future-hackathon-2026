// Riverpod for all state management — providers are declared at the top level
// and accessed anywhere in the widget tree via ref.watch() or ref.read()
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../models/agent_step.dart';      // Enum for the 5 pipeline stages
import '../models/chat_message.dart';    // ChatMessage model for global chat history
import '../models/lat_lng.dart';         // Lightweight lat/lng model for AOI points
import '../services/api_service.dart';   // HTTP client for /api/analyze and /api/chat
import '../services/project_service.dart'; // Firestore CRUD for the projects collection

// ---------------------------------------------------------------------------
// API Service provider (singleton)
// ---------------------------------------------------------------------------
// Single ApiService instance shared across the app — avoids re-creating the
// HTTP client on every widget rebuild
final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

// ---------------------------------------------------------------------------
// Project Service provider (singleton)
// ---------------------------------------------------------------------------
// Single ProjectService instance shared across the app — holds the Firestore
// collection reference and is reused by all project-related operations
final projectServiceProvider = Provider<ProjectService>(
  (ref) => ProjectService(),
);

// ---------------------------------------------------------------------------
// Projects state — real-time stream from Firestore
// ---------------------------------------------------------------------------

/// StreamProvider that listens to real-time updates from the
/// `projects` collection in Firestore.
// Automatically rebuilds any widget that watches this provider whenever
// Firestore emits a new snapshot (e.g. after a report is saved by the backend)
final projectListProvider = StreamProvider<List<Project>>((ref) {
  final service = ref.watch(projectServiceProvider);
  return service.streamProjects();
});

// ---------------------------------------------------------------------------
// Current agent step (per-project, per-analysis tracking)
// ---------------------------------------------------------------------------
// Tracks which of the 5 pipeline stages is currently active for the stepper UI
// Keyed by projectId so two projects can show different steps simultaneously
// Null means no analysis is running
final currentAgentStepProvider = StateProvider.family<AgentStep?, String>(
  (ref, projectId) => null,
);

// ---------------------------------------------------------------------------
// Analysis result (per-project markdown from Documentarian)
// ---------------------------------------------------------------------------
// Stores the Markdown business plan returned by the Documentarian agent
// Keyed by projectId so each project has its own independent report state
// Empty string means no analysis has been run yet in this session
final analysisResultProvider = StateProvider.family<String, String>(
  (ref, projectId) => '',
);

// ---------------------------------------------------------------------------
// Latest planting grid (per-project, fresh from analyze response)
// ---------------------------------------------------------------------------
// Stores the planting grid dict returned by the Plotter's calculate_planting_grid tool
// Keyed by projectId to prevent grid data from one project leaking into another
// Null means no grid has been generated yet in this session
final latestPlantingGridProvider = StateProvider.family<Map<String, dynamic>?, String>(
  (ref, projectId) => null,
);

// ---------------------------------------------------------------------------
// Loading state for chat (per-project)
// ---------------------------------------------------------------------------
// True while the full analysis pipeline is running — disables the input bar
// and shows the AgentStepper modal. Keyed by projectId for isolation.
final isAnalyzingProvider = StateProvider.family<bool, String>(
  (ref, projectId) => false,
);

// ---------------------------------------------------------------------------
// Geospatial state — AOI (Area of Interest) boundary & computed area
// (per-project)
// ---------------------------------------------------------------------------

/// The list of boundary points drawn on the interactive map.
// Each tap on the Google Map appends a LatLng to this list
// Keyed by projectId so drawing in Project A does not affect Project B
final aoiPointsProvider = StateProvider.family<List<LatLng>, String>(
  (ref, projectId) => [],
);

/// The computed land area (in hectares) derived from the AOI polygon.
// Recalculated via spherical-excess formula each time aoiPointsProvider changes
// Keyed by projectId for per-project isolation
final landAreaProvider = StateProvider.family<double, String>(
  (ref, projectId) => 0.0,
);

// ---------------------------------------------------------------------------
// Chat conversation history (persisted in-memory for the session)
// ---------------------------------------------------------------------------
// Global chat history — used by the main analysis conversation thread
// Not keyed by projectId; shared across the whole session
final chatHistoryProvider = StateProvider<List<ChatMessage>>(
  (ref) => [],
);

// ---------------------------------------------------------------------------
// Per-project chatbot thread (lightweight /api/chat endpoint)
// ---------------------------------------------------------------------------

/// Per-project chat thread (list of {role: 'user'|'assistant', content: String})
// Stores the full message history for the Chatbot tab as simple string maps
// Keyed by projectId so each project has its own independent chat thread
final projectChatHistoryProvider =
    StateProvider.family<List<Map<String, String>>, String>(
  (ref, projectId) => [],
);

/// Per-project flag for "chat is waiting for a response"
// True while waiting for /api/chat to respond — shows the typing indicator
// and disables the Send button. Keyed by projectId for isolation.
final isChattingProvider = StateProvider.family<bool, String>(
  (ref, projectId) => false,
);