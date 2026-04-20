import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:http/http.dart' as http;

import '../theme.dart';
import '../models/agent_step.dart';
import '../models/chat_message.dart';
import '../models/lat_lng.dart' as app;
import '../providers/app_providers.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/glass_card.dart';
import '../widgets/agent_stepper.dart';

/// The main analysis interface at route "/project/:id".
class ProjectScreen extends ConsumerStatefulWidget {
  final String projectId;

  const ProjectScreen({super.key, required this.projectId});

  @override
  ConsumerState<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends ConsumerState<ProjectScreen> {
  final _messageController = TextEditingController();
  final _chatController = TextEditingController();

  @override
  void dispose() {
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
      loading: () => const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.accent),
        ),
      ),
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
        final project =
            projects.where((p) => p.id == widget.projectId).firstOrNull;

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
          extendBodyBehindAppBar: true,
          appBar: const AppTopBar(showDashboardButton: true),
          body: Padding(
            padding: const EdgeInsets.only(top: 64),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 900;
                if (isWide) {
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
    final boundariesStr =
        points.map((p) => '[${p.latitude}, ${p.longitude}]').join(', ');

    final formattedMessage = '''
System Context:
- Land Area: ${area.toStringAsFixed(2)} Hectares
- Boundaries: $boundariesStr

User Request: $message''';

    // ── 3. State updates ─────────────────────────────────────────────────
    _messageController.clear();

    final history = [...ref.read(chatHistoryProvider)];
    history.add(ChatMessage(
      role: ChatRole.user,
      content: message,
      timestamp: DateTime.now(),
    ));
    ref.read(chatHistoryProvider.notifier).state = history;

    ref.read(isAnalyzingProvider(projectId).notifier).state = true;
    ref.read(analysisResultProvider(projectId).notifier).state = '';

    // ── 4. Show the pipeline dialog ──────────────────────────────────────
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        builder: (dialogContext) {
          return Consumer(
            builder: (_, dialogRef, __) {
              final step = dialogRef.watch(currentAgentStepProvider(projectId));
              final analyzing = dialogRef.watch(isAnalyzingProvider(projectId));

              return PopScope(
                canPop: !analyzing,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 460,
                      maxHeight: 520,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
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

                                // Stepper content
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
      for (final step in AgentStep.values) {
        ref.read(currentAgentStepProvider(projectId).notifier).state = step;

        if (step == AgentStep.values.last) {
          // On the last step, call the analyze API which also writes to Firestore
          final api = ref.read(apiServiceProvider);
          final result = await api.analyze(
            sessionId: sessionId,
            projectId: projectId,
            message: formattedMessage,
            boundaryPoints: points,
          );
          ref.read(analysisResultProvider(projectId).notifier).state = result.reply;
          ref.read(latestPlantingGridProvider(projectId).notifier).state = result.plantingGrid;

          final updated = [...ref.read(chatHistoryProvider)];
          updated.add(ChatMessage(
            role: ChatRole.assistant,
            content: result.reply,
            timestamp: DateTime.now(),
          ));
          ref.read(chatHistoryProvider.notifier).state = updated;
        } else {
          // Brief delay to visualize each step activating
          await Future.delayed(const Duration(milliseconds: 800));
        }
      }
    } catch (e) {
      // ── 6. Markdown-formatted error feedback ─────────────────────────
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
    final projectsAsync = ref.read(projectListProvider);
    final project = projectsAsync.valueOrNull
        ?.where((p) => p.id == projectId)
        .firstOrNull;
    if (project == null) return;

    // Append user message to chat thread
    ref.read(projectChatHistoryProvider(projectId).notifier).update(
      (prev) => [...prev, {'role': 'user', 'content': text}],
    );
    _chatController.clear();

    ref.read(isChattingProvider(projectId).notifier).state = true;

    try {
      final reply = await api.chat(
        sessionId: project.sessionId,
        message: text,
      );
      ref.read(projectChatHistoryProvider(projectId).notifier).update(
        (prev) => [...prev, {'role': 'assistant', 'content': reply}],
      );
    } catch (e) {
      ref.read(projectChatHistoryProvider(projectId).notifier).update(
        (prev) => [
          ...prev,
          {'role': 'assistant', 'content': '⚠️ Chat failed: $e'},
        ],
      );
    } finally {
      ref.read(isChattingProvider(projectId).notifier).state = false;
    }
  }
}

// ---------------------------------------------------------------------------
// Wide (Desktop) Layout — 2 columns
// ---------------------------------------------------------------------------
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
            flex: 5,
            child: _InteractiveMap(projectId: projectId),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 5,
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
          SizedBox(
            height: 350,
            child: _InteractiveMap(projectId: projectId),
          ),
          const SizedBox(height: 24),
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
  final Completer<gmaps.GoogleMapController> _mapController = Completer();

  // Default camera: center of Peninsular Malaysia
  static const _initialPosition = gmaps.CameraPosition(
    target: gmaps.LatLng(4.2105, 108.9758),
    zoom: 6,
  );

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

  void _onMapTap(gmaps.LatLng position) {
    final points = [...ref.read(aoiPointsProvider(_pid))];
    points.add(app.LatLng(position.latitude, position.longitude));
    ref.read(aoiPointsProvider(_pid).notifier).state = points;
    ref.read(landAreaProvider(_pid).notifier).state = _computeAreaHectares(points);
  }

  void _undoLastPoint() {
    final points = [...ref.read(aoiPointsProvider(_pid))];
    if (points.isEmpty) return;
    points.removeLast();
    ref.read(aoiPointsProvider(_pid).notifier).state = points;
    ref.read(landAreaProvider(_pid).notifier).state = _computeAreaHectares(points);
  }

  void _clearAll() {
    ref.read(aoiPointsProvider(_pid).notifier).state = [];
    ref.read(landAreaProvider(_pid).notifier).state = 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final points = ref.watch(aoiPointsProvider(_pid));
    final area = ref.watch(landAreaProvider(_pid));

    // ── Resolve planting grid (fresh provider > persisted project) ──────
    final freshGrid = ref.watch(latestPlantingGridProvider(_pid));
    final projectsAsync = ref.watch(projectListProvider);
    Map<String, dynamic>? grid = freshGrid;
    if (grid == null) {
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
    final markers = <gmaps.Marker>{};
    for (int i = 0; i < points.length; i++) {
      markers.add(
        gmaps.Marker(
          markerId: gmaps.MarkerId('aoi_$i'),
          position: gmaps.LatLng(points[i].latitude, points[i].longitude),
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
            i == 0
                ? gmaps.BitmapDescriptor.hueGreen
                : gmaps.BitmapDescriptor.hueAzure,
          ),
        ),
      );
    }

    // ── Build planting grid circles (web-safe, no BitmapDescriptor) ─────
    final gridCircles = <gmaps.Circle>{};
    if (grid != null) {
      final timber = (grid!['timber_positions'] as List?) ?? [];
      final intercrop = (grid!['intercrop_positions'] as List?) ?? [];

      for (var i = 0; i < timber.length; i++) {
        final p = timber[i] as Map;
        gridCircles.add(gmaps.Circle(
          circleId: gmaps.CircleId('timber_$i'),
          center: gmaps.LatLng(
            (p['latitude'] as num).toDouble(),
            (p['longitude'] as num).toDouble(),
          ),
          radius: 0.5,
          fillColor: Colors.green,
          strokeColor: Colors.green.shade900,
          strokeWidth: 1,
        ));
      }

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

    // Build polygon
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
          fillColor: AppTheme.accent.withValues(alpha: 0.2),
        ),
      );
    }

    // Build polyline (shows edges even with < 3 points)
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
          // Google Map
          gmaps.GoogleMap(
            initialCameraPosition: _initialPosition,
            onMapCreated: (controller) {
              if (!_mapController.isCompleted) {
                _mapController.complete(controller);
              }
            },
            onTap: _onMapTap,
            markers: markers,
            circles: gridCircles,
            polygons: polygons,
            polylines: polylines,
            mapType: gmaps.MapType.hybrid,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          // Top-center: map search bar
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: _MapSearchBar(
                onLocated: (gmaps.LatLng target) async {
                  final controller = await _mapController.future;
                  await controller.animateCamera(
                    gmaps.CameraUpdate.newLatLngZoom(target, 15),
                  );
                },
              ),
            ),
          ),

          // Top-left: instructions / area badge
          Positioned(
            top: 64,
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

          // Top-right: undo / clear buttons
          if (points.isNotEmpty)
            Positioned(
              top: 64,
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
                    color: AppTheme.error,
                  ),
                ],
              ),
            ),

          // Bottom-left: planting grid legend
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
                    _LegendRow(
                      color: Colors.green,
                      label: 'Timber (${grid!['timber_count']})',
                    ),
                    const SizedBox(height: 6),
                    _LegendRow(
                      color: Colors.amber,
                      label: 'Intercrop (${grid!['intercrop_count']})',
                    ),
                    const SizedBox(height: 6),
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
  bool _loading = false;

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() => _loading = true);
    try {
      // Try direct coordinate parse first: "lat, lng" or "lat lng"
      final coordMatch = RegExp(
        r'^\s*(-?\d+(?:\.\d+)?)\s*[°]?\s*[,\s]\s*(-?\d+(?:\.\d+)?)\s*[°]?\s*$',
      ).firstMatch(query);

      gmaps.LatLng? target;
      if (coordMatch != null) {
        final lat = double.parse(coordMatch.group(1)!);
        final lng = double.parse(coordMatch.group(2)!);
        if (lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
          target = gmaps.LatLng(lat, lng);
        }
      }

      if (target == null) {
        // Geocode via backend proxy (keeps API key server-side)
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

        final loc = results[0]['geometry']['location'];
        target = gmaps.LatLng(
          (loc['lat'] as num).toDouble(),
          (loc['lng'] as num).toDouble(),
        );
      }

      await widget.onLocated(target);
    } catch (e) {
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
              onSubmitted: (_) => _search(),
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
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
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
    if (widget.analysisResult.isNotEmpty) return widget.analysisResult;
    final saved = widget.project.reportMarkdown as String?;
    if (saved != null && saved.isNotEmpty) return saved;
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
          // Project title row
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

          // Tab bar
          _TabBarHeader(controller: _tabController),
          const SizedBox(height: 12),

          // Tab views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _ReportTab(
                  project: widget.project,
                  reportMarkdown: report,
                  isAnalyzing: widget.isAnalyzing,
                  messageController: widget.messageController,
                  onSend: widget.onSend,
                ),
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
        indicator: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppTheme.accent.withValues(alpha: 0.5),
          ),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
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
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        tabs: const [
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

  MarkdownStyleSheet _buildMarkdownStyle() {
    return MarkdownStyleSheet(
      h1: GoogleFonts.inter(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: AppTheme.textPrimary,
        height: 1.3,
      ),
      h1Align: WrapAlignment.center,
      h2: GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary,
        height: 1.4,
      ),
      h3: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppTheme.textPrimary,
      ),
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
      strong: GoogleFonts.inter(
        fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary,
      ),
      em: GoogleFonts.inter(
        fontStyle: FontStyle.italic,
        color: AppTheme.textSecondary,
      ),
      blockquote: GoogleFonts.inter(
        fontSize: 14,
        color: AppTheme.textSecondary,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.08),
        border: Border(
          left: BorderSide(color: AppTheme.accent, width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.all(12),
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
      code: GoogleFonts.firaCode(
        fontSize: 13,
        color: AppTheme.accentLight,
        backgroundColor: AppTheme.surface,
      ),
      codeblockPadding: const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(
        color: AppTheme.deepDark.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
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
                enabled: !isAnalyzing,
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
                onPressed: isAnalyzing ? null : onSend,
                icon: const Icon(Icons.send_rounded, size: 20),
                label: const Text('Analyze'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (reportMarkdown != null && reportMarkdown!.isNotEmpty) {
      return Markdown(
        data: reportMarkdown!,
        selectable: true,
        padding: EdgeInsets.zero,
        styleSheet: _buildMarkdownStyle(),
      );
    }

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
  final _scrollController = ScrollController();

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

    // Auto-scroll when new messages arrive
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
                    itemCount: chatThread.length + (isChatting ? 1 : 0),
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      // Typing indicator at the bottom
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

                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: ConstrainedBox(
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
                              color: isUser
                                  ? AppTheme.accent
                                      .withValues(alpha: 0.25)
                                  : AppTheme.surface
                                      .withValues(alpha: 0.6),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(12),
                                topRight: const Radius.circular(12),
                                bottomLeft:
                                    Radius.circular(isUser ? 12 : 2),
                                bottomRight:
                                    Radius.circular(isUser ? 2 : 12),
                              ),
                              border: Border.all(
                                color: isUser
                                    ? AppTheme.accent
                                        .withValues(alpha: 0.4)
                                    : Colors.white
                                        .withValues(alpha: 0.08),
                              ),
                            ),
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
                  enabled: !isChatting,
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
                  onPressed: isChatting ? null : widget.onChatSend,
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
class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendRow({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
