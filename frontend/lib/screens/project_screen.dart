import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// Riverpod for reading and watching per-project state providers
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Renders the AI-generated Markdown business plan
import 'package:flutter_markdown/flutter_markdown.dart';

// Inter and Fira Code fonts used throughout the screen
import 'package:google_fonts/google_fonts.dart';

// Google Maps Flutter for the interactive AOI boundary map
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;

// HTTP client for the geocoding proxy call in the search bar
import 'package:http/http.dart' as http;

import '../theme.dart';
import '../models/agent_step.dart';    // Enum for the 5 pipeline stages
import '../models/chat_message.dart';  // ChatMessage model for global chat history
import '../models/lat_lng.dart' as app; // App-specific LatLng (avoids gmaps conflict)
import '../providers/app_providers.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/glass_card.dart';
import '../widgets/agent_stepper.dart'; // Visual progress indicator for the pipeline

/// The main analysis interface at route "/project/:id".
class ProjectScreen extends ConsumerStatefulWidget {
  final String projectId;

  const ProjectScreen({super.key, required this.projectId});

  @override
  ConsumerState<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends ConsumerState<ProjectScreen> {
  // Text controller for the analysis input bar (Report tab)
  final _messageController = TextEditingController();

  // Text controller for the chatbot input bar (Chatbot tab)
  final _chatController = TextEditingController();

  @override
  void dispose() {
    // Always dispose controllers to avoid memory leaks
    _messageController.dispose();
    _chatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(projectListProvider);
    final analysisResult = ref.watch(analysisResultProvider(widget.projectId));
    final isAnalyzing = ref.watch(isAnalyzingProvider(widget.projectId));
    final chatHistory = ref.watch(chatHistoryProvider);

    return projectsAsync.when(
      // Show a spinner while the Firestore stream is loading
      loading: () => const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.accent),
        ),
      ),
      // Show an error message if the Firestore stream fails
      error: (err, stack) => Scaffold(
        appBar: const AppTopBar(),
        body: Center(
          child: Text(
            'Error: $err',
            style: GoogleFonts.inter(color: AppTheme.error),
          ),
        ),
      ),
      data: (projects) {
        // Look up this specific project by ID from the full project list
        final project =
            projects.where((p) => p.id == widget.projectId).firstOrNull;

        // Handle the case where the project was deleted or not found
        if (project == null) {
          return Scaffold(
            appBar: const AppTopBar(),
            body: Center(
              child: Text(
                'Project not found',
                style: GoogleFonts.inter(color: AppTheme.textSecondary),
              ),
            ),
          );
        }

        return Scaffold(
          extendBodyBehindAppBar: true, // Map extends behind the transparent app bar
          appBar: const AppTopBar(showDashboardButton: true),
          body: Padding(
            padding: const EdgeInsets.only(top: 64), // Offset for the 64px app bar height
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Switch between wide (desktop) and narrow (mobile) layouts at 900px
                final isWide = constraints.maxWidth > 900;
                if (isWide) {
                  // Desktop: map and command center side by side
                  return _WideLayout(
                    projectId: widget.projectId,
                    project: project,
                    analysisResult: analysisResult,
                    isAnalyzing: isAnalyzing,
                    chatHistory: chatHistory,
                    messageController: _messageController,
                    onSend: () => _sendMessage(project.id, project.sessionId),
                    chatController: _chatController,
                    onChatSend: () => _sendChatMessage(),
                  );
                } else {
                  // Mobile: map stacked above command center
                  return _NarrowLayout(
                    projectId: widget.projectId,
                    project: project,
                    analysisResult: analysisResult,
                    isAnalyzing: isAnalyzing,
                    chatHistory: chatHistory,
                    messageController: _messageController,
                    onSend: () => _sendMessage(project.id, project.sessionId),
                    chatController: _chatController,
                    onChatSend: () => _sendChatMessage(),
                  );
                }
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _sendMessage(String projectId, String sessionId) async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    // ── 1. Validate geospatial data ──────────────────────────────────────
    // Block the request if the user hasn't drawn a boundary on the map yet
    final points = ref.read(aoiPointsProvider(projectId));
    final area = ref.read(landAreaProvider(projectId));

    if (area == 0.0 || points.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Please draw your farm boundary on the map before analyzing.',
            ),
            backgroundColor: Colors.redAccent.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // ── 2. Format payload with system context ────────────────────────────
    // Prepend geospatial context so the Land Profiler agent knows the farm location
    final boundariesStr =
        points.map((p) => '[${p.latitude}, ${p.longitude}]').join(', ');

    final formattedMessage = '''
System Context:
- Land Area: ${area.toStringAsFixed(2)} Hectares
- Boundaries: $boundariesStr

User Request: $message''';

    // ── 3. State updates ─────────────────────────────────────────────────
    _messageController.clear();

    // Add the user message to the global chat history
    final history = [...ref.read(chatHistoryProvider)];
    history.add(ChatMessage(
      role: ChatRole.user,
      content: message,
      timestamp: DateTime.now(),
    ));
    ref.read(chatHistoryProvider.notifier).state = history;

    // Set analyzing state to true — disables input bar and shows stepper modal
    ref.read(isAnalyzingProvider(projectId).notifier).state = true;

    // Clear any previous analysis result before starting a new one
    ref.read(analysisResultProvider(projectId).notifier).state = '';

    // ── 4. Show the pipeline dialog ──────────────────────────────────────
    // Non-dismissible glassmorphic modal showing the AgentStepper progress UI
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false, // User cannot dismiss while pipeline is running
        barrierColor: Colors.black.withValues(alpha: 0.6),
        builder: (dialogContext) {
          return Consumer(
            builder: (_, dialogRef, __) {
              // Watch both step and analyzing state to update the dialog reactively
              final step = dialogRef.watch(currentAgentStepProvider(projectId));
              final analyzing = dialogRef.watch(isAnalyzingProvider(projectId));

              return PopScope(
                canPop: !analyzing, // Prevent back-button dismiss during analysis
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 460,
                      maxHeight: 520,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        // Glassmorphic blur effect for the modal background
                        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppTheme.surface.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 32,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(28),
                          child: Material(
                            color: Colors.transparent,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppTheme.accent.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppTheme.accent.withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.auto_awesome_rounded,
                                        size: 20,
                                        color: AppTheme.accentLight,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'AI Analysis Pipeline',
                                            style: GoogleFonts.inter(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Processing your land analysis…',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Only show the close button after analysis completes
                                    if (!analyzing)
                                      IconButton(
                                        onPressed: () => Navigator.of(dialogContext).pop(),
                                        icon: const Icon(Icons.close_rounded, size: 20),
                                        color: AppTheme.textSecondary,
                                        tooltip: 'Close',
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 24),

                                // Divider
                                Container(
                                  height: 1,
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                                const SizedBox(height: 24),

                                // Stepper content — shows which pipeline stage is active
                                Flexible(
                                  child: SingleChildScrollView(
                                    child: AgentStepper(currentStep: step),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    }

    try {
      // ── 5. Animate through the agent stepper ─────────────────────────
      // Step through each AgentStep enum value to animate the stepper UI
      for (final step in AgentStep.values) {
        ref.read(currentAgentStepProvider(projectId).notifier).state = step;

        if (step == AgentStep.values.last) {
          // On the final step, fire the actual API call to the backend
          // This also triggers the backend to write results to Firestore
          final api = ref.read(apiServiceProvider);
          final result = await api.analyze(
            sessionId: sessionId,
            projectId: projectId,
            message: formattedMessage,
            boundaryPoints: points,
          );
          // Store the Markdown report for the Report tab
          ref.read(analysisResultProvider(projectId).notifier).state = result.reply;

          // Store the planting grid for rendering circles on the map
          ref.read(latestPlantingGridProvider(projectId).notifier).state = result.plantingGrid;

          // Append the assistant reply to the global chat history
          final updated = [...ref.read(chatHistoryProvider)];
          updated.add(ChatMessage(
            role: ChatRole.assistant,
            content: result.reply,
            timestamp: DateTime.now(),
          ));
          ref.read(chatHistoryProvider.notifier).state = updated;
        } else {
          // Brief delay to visualize each step activating in the stepper UI
          await Future.delayed(const Duration(milliseconds: 800));
        }
      }
    } catch (e) {
      // ── 6. Markdown-formatted error feedback ─────────────────────────
      // Display a structured error message in the Report tab with troubleshooting tips
      final errorMd = '''
## ⚠️ Analysis Failed

**Error:** ${e.toString()}

---

### Troubleshooting
- Ensure the backend is running at `http://localhost:8000`
- Check your network connection
- Verify the API endpoint is accessible

> *If the issue persists, please restart the backend server and try again.*
''';
      ref.read(analysisResultProvider(projectId).notifier).state = errorMd;

      final updated = [...ref.read(chatHistoryProvider)];
      updated.add(ChatMessage(
        role: ChatRole.assistant,
        content: errorMd,
        timestamp: DateTime.now(),
      ));
      ref.read(chatHistoryProvider.notifier).state = updated;
    } finally {
      // Always reset the analyzing flag regardless of success or failure
      ref.read(isAnalyzingProvider(projectId).notifier).state = false;

      // ── 7. Auto-close the dialog ─────────────────────────────────────
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  /// Lightweight chat send — calls /api/chat (NOT the full analyze pipeline).
  Future<void> _sendChatMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    final projectId = widget.projectId;
    final api = ref.read(apiServiceProvider);

    // Look up project to get sessionId
    // sessionId links this chat to the same Vertex AI session as the analysis
    final projectsAsync = ref.read(projectListProvider);
    final project = projectsAsync.valueOrNull
        ?.where((p) => p.id == projectId)
        .firstOrNull;
    if (project == null) return;

    // Append user message to chat thread immediately for responsive UI
    ref.read(projectChatHistoryProvider(projectId).notifier).update(
      (prev) => [...prev, {'role': 'user', 'content': text}],
    );
    _chatController.clear();

    // Show typing indicator while waiting for the backend response
    ref.read(isChattingProvider(projectId).notifier).state = true;

    try {
      // Call the lightweight /api/chat endpoint — much faster than /api/analyze
      final reply = await api.chat(
        sessionId: project.sessionId,
        message: text,
      );
      // Append the assistant reply to the per-project chat thread
      ref.read(projectChatHistoryProvider(projectId).notifier).update(
        (prev) => [...prev, {'role': 'assistant', 'content': reply}],
      );
    } catch (e) {
      // Append an inline error message so the user knows the chat failed
      ref.read(projectChatHistoryProvider(projectId).notifier).update(
        (prev) => [
          ...prev,
          {'role': 'assistant', 'content': '⚠️ Chat failed: $e'},
        ],
      );
    } finally {
      // Always reset the chatting flag regardless of success or failure
      ref.read(isChattingProvider(projectId).notifier).state = false;
    }
  }
}

// ---------------------------------------------------------------------------
// Wide (Desktop) Layout — 2 columns
// ---------------------------------------------------------------------------
// Used when screen width > 900px — map and command center side by side (50/50)
class _WideLayout extends StatelessWidget {
  final String projectId;
  final dynamic project;
  final String analysisResult;
  final bool isAnalyzing;
  final List<ChatMessage> chatHistory;
  final TextEditingController messageController;
  final VoidCallback onSend;
  final TextEditingController chatController;
  final VoidCallback onChatSend;

  const _WideLayout({
    required this.projectId,
    required this.project,
    required this.analysisResult,
    required this.isAnalyzing,
    required this.chatHistory,
    required this.messageController,
    required this.onSend,
    required this.chatController,
    required this.onChatSend,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left pane — full-height interactive map
          Expanded(
            flex: 5, // 50% of available width
            child: _InteractiveMap(projectId: projectId),
          ),
          const SizedBox(width: 24),
          // Right pane — tabbed AI analysis command center
          Expanded(
            flex: 5, // 50% of available width
            child: _RightTabContainer(
              projectId: projectId,
              project: project,
              analysisResult: analysisResult,
              isAnalyzing: isAnalyzing,
              chatHistory: chatHistory,
              messageController: messageController,
              onSend: onSend,
              chatController: chatController,
              onChatSend: onChatSend,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Narrow (Mobile) Layout — stacked
// ---------------------------------------------------------------------------
// Used when screen width <= 900px — map on top, command center below
class _NarrowLayout extends StatelessWidget {
  final String projectId;
  final dynamic project;
  final String analysisResult;
  final bool isAnalyzing;
  final List<ChatMessage> chatHistory;
  final TextEditingController messageController;
  final VoidCallback onSend;
  final TextEditingController chatController;
  final VoidCallback onChatSend;

  const _NarrowLayout({
    required this.projectId,
    required this.project,
    required this.analysisResult,
    required this.isAnalyzing,
    required this.chatHistory,
    required this.messageController,
    required this.onSend,
    required this.chatController,
    required this.onChatSend,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Fixed-height map on mobile to leave room for the command center
          SizedBox(
            height: 350,
            child: _InteractiveMap(projectId: projectId),
          ),
          const SizedBox(height: 24),
          // Command center height fills remaining screen space
          SizedBox(
            height: MediaQuery.of(context).size.height - 150,
            child: _RightTabContainer(
              projectId: projectId,
              project: project,
              analysisResult: analysisResult,
              isAnalyzing: isAnalyzing,
              chatHistory: chatHistory,
              messageController: messageController,
              onSend: onSend,
              chatController: chatController,
              onChatSend: onChatSend,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Interactive Map — tap to draw AOI polygon
// ---------------------------------------------------------------------------
class _InteractiveMap extends ConsumerStatefulWidget {
  final String projectId;
  const _InteractiveMap({required this.projectId});

  @override
  ConsumerState<_InteractiveMap> createState() => _InteractiveMapState();
}

class _InteractiveMapState extends ConsumerState<_InteractiveMap> {
  // Completer allows the search bar to animate the camera after map creation
  final Completer<gmaps.GoogleMapController> _mapController = Completer();

  // Default camera: center of Peninsular Malaysia
  static const _initialPosition = gmaps.CameraPosition(
    target: gmaps.LatLng(4.2105, 108.9758),
    zoom: 6, // Country-level zoom — user pans to their farm location
  );

  // Shorthand getter to avoid repeating widget.projectId throughout the class
  String get _pid => widget.projectId;

  /// Compute polygon area in hectares using the Shoelace formula on a sphere.
  double _computeAreaHectares(List<app.LatLng> pts) {
    if (pts.length < 3) return 0.0;
    const double earthRadius = 6371000; // meters
    double toRad(double deg) => deg * math.pi / 180.0;

    // Spherical excess method (more accurate for geodetic polygons)
    double total = 0.0;
    final n = pts.length;
    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      total += toRad(pts[j].longitude - pts[i].longitude) *
          (2 + math.sin(toRad(pts[i].latitude)) +
              math.sin(toRad(pts[j].latitude)));
    }
    total = (total * earthRadius * earthRadius / 2.0).abs();
    return total / 10000.0; // m² → hectares
  }

  // Adds a new boundary point when the user taps on the map
  void _onMapTap(gmaps.LatLng position) {
    final points = [...ref.read(aoiPointsProvider(_pid))];
    points.add(app.LatLng(position.latitude, position.longitude));
    ref.read(aoiPointsProvider(_pid).notifier).state = points;
    // Recompute area every time the polygon changes
    ref.read(landAreaProvider(_pid).notifier).state = _computeAreaHectares(points);
  }

  // Removes the most recently added boundary point
  void _undoLastPoint() {
    final points = [...ref.read(aoiPointsProvider(_pid))];
    if (points.isEmpty) return;
    points.removeLast();
    ref.read(aoiPointsProvider(_pid).notifier).state = points;
    ref.read(landAreaProvider(_pid).notifier).state = _computeAreaHectares(points);
  }

  // Removes all boundary points and resets the area to zero
  void _clearAll() {
    ref.read(aoiPointsProvider(_pid).notifier).state = [];
    ref.read(landAreaProvider(_pid).notifier).state = 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final points = ref.watch(aoiPointsProvider(_pid));
    final area = ref.watch(landAreaProvider(_pid));

    // ── Resolve planting grid (fresh provider > persisted project) ──────
    // Priority: in-memory grid from the latest analysis > persisted Firestore grid
    final freshGrid = ref.watch(latestPlantingGridProvider(_pid));
    final projectsAsync = ref.watch(projectListProvider);
    Map<String, dynamic>? grid = freshGrid;
    if (grid == null) {
      // Fall back to the Firestore-persisted grid if no fresh grid exists
      projectsAsync.whenData((projects) {
        for (final p in projects) {
          if (p.id == _pid && p.plantingGrid != null) {
            grid = p.plantingGrid;
            break;
          }
        }
      });
    }

    // Build AOI boundary markers (corner pins only)
    // First point is green to indicate the polygon start; others are azure
    final markers = <gmaps.Marker>{};
    for (int i = 0; i < points.length; i++) {
      markers.add(
        gmaps.Marker(
          markerId: gmaps.MarkerId('aoi_$i'),
          position: gmaps.LatLng(points[i].latitude, points[i].longitude),
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
            i == 0
                ? gmaps.BitmapDescriptor.hueGreen  // First point: green
                : gmaps.BitmapDescriptor.hueAzure, // Subsequent points: azure
          ),
        ),
      );
    }

    // ── Build planting grid circles (web-safe, no BitmapDescriptor) ─────
    // Uses Circle overlays instead of Markers — more reliable on Flutter Web
    final gridCircles = <gmaps.Circle>{};
    if (grid != null) {
      final timber = (grid!['timber_positions'] as List?) ?? [];
      final intercrop = (grid!['intercrop_positions'] as List?) ?? [];

      // Render each timber position as a green circle
      for (var i = 0; i < timber.length; i++) {
        final p = timber[i] as Map;
        gridCircles.add(gmaps.Circle(
          circleId: gmaps.CircleId('timber_$i'),
          center: gmaps.LatLng(
            (p['latitude'] as num).toDouble(),
            (p['longitude'] as num).toDouble(),
          ),
          radius: 0.5,               // 0.5m radius — visible at high zoom levels
          fillColor: Colors.green,
          strokeColor: Colors.green.shade900,
          strokeWidth: 1,
        ));
      }

      // Render each intercrop position as an amber circle
      for (var i = 0; i < intercrop.length; i++) {
        final p = intercrop[i] as Map;
        gridCircles.add(gmaps.Circle(
          circleId: gmaps.CircleId('intercrop_$i'),
          center: gmaps.LatLng(
            (p['latitude'] as num).toDouble(),
            (p['longitude'] as num).toDouble(),
          ),
          radius: 0.5,
          fillColor: Colors.amber,
          strokeColor: Colors.amber.shade900,
          strokeWidth: 1,
        ));
      }
    }

    // Build polygon overlay — only shown when 3+ boundary points exist
    final polygons = <gmaps.Polygon>{};
    if (points.length >= 3) {
      polygons.add(
        gmaps.Polygon(
          polygonId: const gmaps.PolygonId('aoi'),
          points: points
              .map((p) => gmaps.LatLng(p.latitude, p.longitude))
              .toList(),
          strokeColor: AppTheme.accent,
          strokeWidth: 2,
          fillColor: AppTheme.accent.withValues(alpha: 0.2), // Semi-transparent blue fill
        ),
      );
    }

    // Build polyline — shows connecting edges even before a closed polygon (< 3 pts)
    final polylines = <gmaps.Polyline>{};
    if (points.length >= 2) {
      polylines.add(
        gmaps.Polyline(
          polylineId: const gmaps.PolylineId('aoi_line'),
          points: points
              .map((p) => gmaps.LatLng(p.latitude, p.longitude))
              .toList(),
          color: AppTheme.accent,
          width: 2,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          // Google Map — hybrid (satellite + roads) for accurate farm boundary drawing
          gmaps.GoogleMap(
            initialCameraPosition: _initialPosition,
            onMapCreated: (controller) {
              // Complete the Completer only once — guards against duplicate calls
              if (!_mapController.isCompleted) {
                _mapController.complete(controller);
              }
            },
            onTap: _onMapTap,      // Each tap adds a boundary point
            markers: markers,       // Corner pins for the AOI boundary
            circles: gridCircles,   // Planting grid dots (timber + intercrop)
            polygons: polygons,     // Filled AOI polygon (3+ points)
            polylines: polylines,   // Connecting edges (2+ points)
            mapType: gmaps.MapType.hybrid,  // Satellite + road labels
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          // Top-center: map search bar — accepts place names or raw coordinates
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: _MapSearchBar(
                onLocated: (gmaps.LatLng target) async {
                  // Animate the camera to the geocoded location at street level
                  final controller = await _mapController.future;
                  await controller.animateCamera(
                    gmaps.CameraUpdate.newLatLngZoom(target, 15),
                  );
                },
              ),
            ),
          ),

          // Top-left: instructions / area badge
          // Shows guidance when empty, point count while drawing, area when complete
          Positioned(
            top: 64, // Offset below the search bar
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.deepDark.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    points.isEmpty ? Icons.touch_app_rounded : Icons.straighten,
                    size: 16,
                    color: AppTheme.accentLight,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    points.isEmpty
                        ? 'Tap on the map to draw boundary'
                        : points.length < 3
                            ? '${points.length} point${points.length > 1 ? 's' : ''} — need at least 3'
                            : '${area.toStringAsFixed(2)} ha  (${points.length} pts)',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Top-right: undo / clear buttons — only shown when points exist
          if (points.isNotEmpty)
            Positioned(
              top: 64, // Aligned with the area badge
              right: 12,
              child: Row(
                children: [
                  _mapButton(
                    icon: Icons.undo_rounded,
                    tooltip: 'Undo last point',
                    onTap: _undoLastPoint,
                  ),
                  const SizedBox(width: 8),
                  _mapButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Clear all',
                    onTap: _clearAll,
                    color: AppTheme.error, // Red to signal destructive action
                  ),
                ],
              ),
            ),

          // Bottom-left: planting grid legend — only shown when grid data exists
          if (grid != null)
            Positioned(
              bottom: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Green dot + timber count
                    _LegendRow(
                      color: Colors.green,
                      label: 'Timber (${grid!['timber_count']})',
                    ),
                    const SizedBox(height: 6),
                    // Amber dot + intercrop count
                    _LegendRow(
                      color: Colors.amber,
                      label: 'Intercrop (${grid!['intercrop_count']})',
                    ),
                    const SizedBox(height: 6),
                    // Summary line: total plants and spacing
                    Text(
                      '${grid!['total_plants']} plants @ ${grid!['spacing_meters']}m',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Helper to build a consistent small icon button for the map overlay controls
  Widget _mapButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color color = AppTheme.accentLight,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppTheme.deepDark.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Map search bar — place name or coordinate input
// ---------------------------------------------------------------------------
class _MapSearchBar extends StatefulWidget {
  final Future<void> Function(gmaps.LatLng target) onLocated;
  const _MapSearchBar({required this.onLocated});

  @override
  State<_MapSearchBar> createState() => _MapSearchBarState();
}

class _MapSearchBarState extends State<_MapSearchBar> {
  final _controller = TextEditingController();
  bool _loading = false; // True while geocoding is in progress

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() => _loading = true);
    try {
      // Try direct coordinate parse first: "lat, lng" or "lat lng"
      // This avoids an unnecessary geocoding API call for coordinate inputs
      final coordMatch = RegExp(
        r'^\s*(-?\d+(?:\.\d+)?)\s*[°]?\s*[,\s]\s*(-?\d+(?:\.\d+)?)\s*[°]?\s*$',
      ).firstMatch(query);

      gmaps.LatLng? target;
      if (coordMatch != null) {
        final lat = double.parse(coordMatch.group(1)!);
        final lng = double.parse(coordMatch.group(2)!);
        // Validate the parsed coordinates are within valid WGS84 bounds
        if (lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
          target = gmaps.LatLng(lat, lng);
        }
      }

      if (target == null) {
        // Geocode via backend proxy (keeps API key server-side)
        // The backend restricts results to Malaysia via components=country:MY
        final uri = Uri.parse('http://localhost:8000/api/geocode');
        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'query': query}),
        );

        if (response.statusCode != 200) {
          throw Exception('Geocoding proxy failed: HTTP ${response.statusCode}');
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // Backend returns Google's raw shape: status, results, error_message
        final status = data['status'];
        if (status != 'OK') {
          final msg = data['error_message'] ?? status ?? 'Unknown error';
          throw Exception('No location found for "$query" ($msg)');
        }

        final results = data['results'] as List?;
        if (results == null || results.isEmpty) {
          throw Exception('No location found for "$query"');
        }

        // Extract the lat/lng from the first geocoding result
        final loc = results[0]['geometry']['location'];
        target = gmaps.LatLng(
          (loc['lat'] as num).toDouble(),
          (loc['lng'] as num).toDouble(),
        );
      }

      // Animate the map camera to the resolved location
      await widget.onLocated(target);
    } catch (e) {
      // Show a red SnackBar with the error message if geocoding fails
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search failed: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      // Always clear the loading state regardless of success or failure
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search, color: Colors.white70, size: 18),
          const SizedBox(width: 6),
          SizedBox(
            width: 280,
            child: TextField(
              controller: _controller,
              onSubmitted: (_) => _search(), // Allow Enter key to trigger search
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Search place or "lat, lng"',
                hintStyle: TextStyle(color: Colors.white54, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Show a spinner while geocoding, arrow button when idle
          _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  icon: const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                  onPressed: _search,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Right Column — Tabbed container ("Report" & "Chatbot")
// ---------------------------------------------------------------------------
class _RightTabContainer extends StatefulWidget {
  final String projectId;
  final dynamic project;
  final String analysisResult;
  final bool isAnalyzing;
  final List<ChatMessage> chatHistory;
  final TextEditingController messageController;
  final VoidCallback onSend;
  final TextEditingController chatController;
  final VoidCallback onChatSend;

  const _RightTabContainer({
    required this.projectId,
    required this.project,
    required this.analysisResult,
    required this.isAnalyzing,
    required this.chatHistory,
    required this.messageController,
    required this.onSend,
    required this.chatController,
    required this.onChatSend,
  });

  @override
  State<_RightTabContainer> createState() => _RightTabContainerState();
}

class _RightTabContainerState extends State<_RightTabContainer>
    with SingleTickerProviderStateMixin {
  // TabController drives both the tab bar indicator and the TabBarView
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    // length: 2 for the Report and Chatbot tabs
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Resolve the most relevant report markdown — fresh session first,
  /// then any persisted Firestore report.
  String? _resolveReport() {
    // Priority 1: Fresh result from the current session (in-memory)
    if (widget.analysisResult.isNotEmpty) return widget.analysisResult;

    // Priority 2: Persisted report saved to Firestore by the backend
    final saved = widget.project.reportMarkdown as String?;
    if (saved != null && saved.isNotEmpty) return saved;

    // Priority 3: No report exists yet
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final report = _resolveReport();

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Project title row — shows screen name and project name
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Analysis Command Center',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                // Project name displayed in accent color below the title
                Text(
                  widget.project.name,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppTheme.accentLight,
                  ),
                ),
              ],
            ),
          ),

          // Tab bar — Report and Chatbot tabs with accent-colored active indicator
          _TabBarHeader(controller: _tabController),
          const SizedBox(height: 12),

          // Tab views — Report and Chatbot content areas
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Report — markdown business plan + analyze input bar
                _ReportTab(
                  project: widget.project,
                  reportMarkdown: report,
                  isAnalyzing: widget.isAnalyzing,
                  messageController: widget.messageController,
                  onSend: widget.onSend,
                ),
                // Tab 2: Chatbot — bubble-style chat thread + send input bar
                _ChatbotTab(
                  projectId: widget.projectId,
                  chatController: widget.chatController,
                  onChatSend: widget.onChatSend,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab bar header — styled with the accent colour for the active tab
// ---------------------------------------------------------------------------
class _TabBarHeader extends StatelessWidget {
  final TabController controller;

  const _TabBarHeader({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.deepDark.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.all(4),
      child: TabBar(
        controller: controller,
        // Custom rounded indicator with accent color instead of the default underline
        indicator: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppTheme.accent.withValues(alpha: 0.5),
          ),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent, // Hide the default divider line
        labelColor: AppTheme.accentLight,
        unselectedLabelColor: AppTheme.textSecondary,
        labelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        splashFactory: NoSplash.splashFactory,   // Disable ink splash on tab press
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        tabs: const [
          // Tab 1: Report — article icon + label
          Tab(
            height: 36,
            icon: null,
            iconMargin: EdgeInsets.zero,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.article_outlined, size: 16),
                SizedBox(width: 6),
                Text('Report'),
              ],
            ),
          ),
          // Tab 2: Chatbot — chat bubble icon + label
          Tab(
            height: 36,
            icon: null,
            iconMargin: EdgeInsets.zero,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 16),
                SizedBox(width: 6),
                Text('Chatbot'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Report Tab — placeholder or rendered markdown plan
// ---------------------------------------------------------------------------
class _ReportTab extends StatelessWidget {
  final dynamic project;
  final String? reportMarkdown;
  final bool isAnalyzing;
  final TextEditingController messageController;
  final VoidCallback onSend;

  const _ReportTab({
    required this.project,
    required this.reportMarkdown,
    required this.isAnalyzing,
    required this.messageController,
    required this.onSend,
  });

  // Custom Markdown stylesheet matching AgroMind's dark glassmorphic design
  MarkdownStyleSheet _buildMarkdownStyle() {
    return MarkdownStyleSheet(
      // Large display heading — used for the business plan title
      h1: GoogleFonts.inter(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: AppTheme.textPrimary,
        height: 1.3,
      ),
      h1Align: WrapAlignment.center,
      // Section headings — used for major plan sections
      h2: GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary,
        height: 1.4,
      ),
      // Sub-section headings
      h3: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppTheme.textPrimary,
      ),
      // Body text — secondary color for comfortable long-form reading
      p: GoogleFonts.inter(
        fontSize: 14,
        color: AppTheme.textSecondary,
        height: 1.7,
      ),
      listBullet: GoogleFonts.inter(
        fontSize: 14,
        color: AppTheme.textSecondary,
        height: 1.7,
      ),
      // Bold text uses primary color to stand out against secondary body text
      strong: GoogleFonts.inter(
        fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary,
      ),
      em: GoogleFonts.inter(
        fontStyle: FontStyle.italic,
        color: AppTheme.textSecondary,
      ),
      // Blockquotes used for agent notes and highlighted recommendations
      blockquote: GoogleFonts.inter(
        fontSize: 14,
        color: AppTheme.textSecondary,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.08),
        border: Border(
          left: BorderSide(color: AppTheme.accent, width: 3), // Accent left border
        ),
      ),
      blockquotePadding: const EdgeInsets.all(12),
      // Table styles — used for financial projections and species comparisons
      tableHead: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary,
      ),
      tableBody: GoogleFonts.inter(
        fontSize: 13,
        color: AppTheme.textSecondary,
        height: 1.5,
      ),
      tableHeadAlign: TextAlign.left,
      tableBorder: TableBorder.all(
        color: Colors.white.withValues(alpha: 0.15),
        width: 1,
      ),
      tableColumnWidth: const IntrinsicColumnWidth(),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      // Inline code — accent color on dark surface background
      code: GoogleFonts.firaCode(
        fontSize: 13,
        color: AppTheme.accentLight,
        backgroundColor: AppTheme.surface,
      ),
      codeblockPadding: const EdgeInsets.all(12),
      // Code block — darker than surface with subtle border
      codeblockDecoration: BoxDecoration(
        color: AppTheme.deepDark.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      // Horizontal rules rendered as subtle white lines between sections
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Report content area (expands to fill) ─────────────────
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.deepDark.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            padding: const EdgeInsets.all(20),
            child: _buildContent(),
          ),
        ),

        // ── Analyze input bar (fixed at bottom) ──────────────────
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: messageController,
                enabled: !isAnalyzing, // Disabled while pipeline is running
                onSubmitted: (_) => onSend(),
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  color: AppTheme.textPrimary,
                ),
                decoration: const InputDecoration(
                  hintText:
                      'Analyze this land for a mix of timber and short-term cash crops…',
                  prefixIcon: Icon(
                    Icons.eco_outlined,
                    color: AppTheme.textSecondary,
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: isAnalyzing ? null : onSend, // Disabled while analyzing
                icon: const Icon(Icons.send_rounded, size: 20),
                label: const Text('Analyze'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Builds the appropriate content widget based on the current state
  Widget _buildContent() {
    // State 1: Report is available — render the Markdown business plan
    if (reportMarkdown != null && reportMarkdown!.isNotEmpty) {
      return Markdown(
        data: reportMarkdown!,
        selectable: true,  // Allow users to copy text from the report
        padding: EdgeInsets.zero,
        styleSheet: _buildMarkdownStyle(),
      );
    }

    // State 2: Analysis is running — show a loading spinner
    if (isAnalyzing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppTheme.accent),
            const SizedBox(height: 16),
            Text(
              'Generating report…',
              style: GoogleFonts.inter(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    // State 3: No report yet — show the empty state illustration
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.description_outlined,
              size: 48,
              color: AppTheme.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No report generated yet.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Draw farm boundary and send an analysis request to see the results.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.textSecondary.withValues(alpha: 0.8),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chatbot Tab — lightweight /api/chat conversation thread
// ---------------------------------------------------------------------------
class _ChatbotTab extends ConsumerStatefulWidget {
  final String projectId;
  final TextEditingController chatController;
  final VoidCallback onChatSend;

  const _ChatbotTab({
    required this.projectId,
    required this.chatController,
    required this.onChatSend,
  });

  @override
  ConsumerState<_ChatbotTab> createState() => _ChatbotTabState();
}

class _ChatbotTabState extends ConsumerState<_ChatbotTab> {
  // ScrollController used to auto-scroll to the latest message
  final _scrollController = ScrollController();

  // Scrolls the chat list to the bottom after the current frame is rendered
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Markdown stylesheet for assistant chat bubbles — tighter than the Report tab style
  MarkdownStyleSheet _assistantStyle() => MarkdownStyleSheet(
        p: GoogleFonts.inter(
          fontSize: 13.5,
          color: AppTheme.textPrimary,
          height: 1.6,
        ),
        h1: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary),
        h2: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary),
        h3: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary),
        listBullet: GoogleFonts.inter(
            fontSize: 13.5, color: AppTheme.textPrimary, height: 1.6),
        strong: GoogleFonts.inter(
            fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
        tableHead: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary),
        tableBody: GoogleFonts.inter(
            fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
        tableBorder: TableBorder.all(
            color: Colors.white.withValues(alpha: 0.1), width: 1),
        tableCellsPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        code: GoogleFonts.firaCode(
            fontSize: 12,
            color: AppTheme.accentLight,
            backgroundColor: AppTheme.surface),
      );

  @override
  Widget build(BuildContext context) {
    final chatThread =
        ref.watch(projectChatHistoryProvider(widget.projectId));
    final isChatting = ref.watch(isChattingProvider(widget.projectId));
    final hasHistory = chatThread.isNotEmpty;

    // Auto-scroll when new messages arrive (list length increases)
    ref.listen<List<Map<String, String>>>(
      projectChatHistoryProvider(widget.projectId),
      (prev, next) {
        if ((prev?.length ?? 0) != next.length) _scrollToBottom();
      },
    );

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.deepDark.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // ── Chat messages area ──────────────────────────────────────
          Expanded(
            child: hasHistory
                ? ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 4),
                    // Extra item at the end for the typing indicator when chatting
                    itemCount: chatThread.length + (isChatting ? 1 : 0),
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      // Typing indicator shown at the bottom while waiting for response
                      if (index >= chatThread.length) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppTheme.surface
                                  .withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.white
                                      .withValues(alpha: 0.08)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.accentLight,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Thinking…',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final msg = chatThread[index];
                      final isUser = msg['role'] == 'user';

                      // Chat bubble — right-aligned for user, left-aligned for assistant
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight   // User messages on the right
                            : Alignment.centerLeft,   // Assistant messages on the left
                        child: ConstrainedBox(
                          // Cap bubble width at 60% of screen width
                          constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width * 0.6,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              // User bubbles: accent blue tint; assistant: surface tint
                              color: isUser
                                  ? AppTheme.accent
                                      .withValues(alpha: 0.25)
                                  : AppTheme.surface
                                      .withValues(alpha: 0.6),
                              // Asymmetric corners create the chat bubble tail effect
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(12),
                                topRight: const Radius.circular(12),
                                bottomLeft:
                                    Radius.circular(isUser ? 12 : 2),  // Tail on left for assistant
                                bottomRight:
                                    Radius.circular(isUser ? 2 : 12),  // Tail on right for user
                              ),
                              border: Border.all(
                                color: isUser
                                    ? AppTheme.accent
                                        .withValues(alpha: 0.4)
                                    : Colors.white
                                        .withValues(alpha: 0.08),
                              ),
                            ),
                            // User messages: plain text; assistant: Markdown for rich formatting
                            child: isUser
                                ? Text(
                                    msg['content'] ?? '',
                                    style: GoogleFonts.inter(
                                      fontSize: 13.5,
                                      color: AppTheme.textPrimary,
                                      height: 1.5,
                                    ),
                                  )
                                : MarkdownBody(
                                    data: msg['content'] ?? '',
                                    selectable: true,
                                    styleSheet: _assistantStyle(),
                                  ),
                          ),
                        ),
                      );
                    },
                  )
                // Empty state — shown before the first message is sent
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.smart_toy_outlined,
                            size: 48,
                            color: AppTheme.textSecondary
                                .withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Ask follow-up questions',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Use this chat to ask quick questions about your analysis results. Responses arrive in seconds.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppTheme.textSecondary
                                  .withValues(alpha: 0.8),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),

          // ── Chat input bar ─────────────────────────────────────────
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.chatController,
                  enabled: !isChatting, // Disabled while waiting for response
                  onSubmitted: (_) => widget.onChatSend(),
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Ask a follow-up question…',
                    prefixIcon: Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: isChatting ? null : widget.onChatSend, // Disabled while chatting
                  icon: const Icon(Icons.send_rounded, size: 20),
                  label: const Text('Send'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


// ---------------------------------------------------------------------------
// Legend row helper — colored dot + label
// ---------------------------------------------------------------------------
// Reusable widget for each row in the planting grid map legend
class _LegendRow extends StatelessWidget {
  final Color color;  // Dot color matching the map circle color
  final String label; // Text label showing plant type and count
  const _LegendRow({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Colored circle dot matching the map circle color
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    );
  }
}