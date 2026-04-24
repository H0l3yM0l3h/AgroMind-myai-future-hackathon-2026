import 'dart:convert';

// http package for making async HTTP requests to the FastAPI backend
import 'package:http/http.dart' as http;

import '../models/lat_lng.dart'; // App-specific LatLng model for boundary points

/// Service class for communicating with the AgroMind FastAPI backend.
class ApiService {
  // Change this to your deployed backend URL in production.
  // In development this points to the local uvicorn server
  static const String _baseUrl = 'http://localhost:8000';

  /// Sends a chat message to the orchestrator and returns the reply.
  ///
  /// [sessionId] ties the request to a persistent conversation session.
  /// [message] is the user's natural-language query.
  // Calls the lightweight /api/chat endpoint — uses the chat agent, NOT the
  // full 5-stage analysis pipeline. Typical response time: 3–5 seconds.
  Future<String> chat({
    required String sessionId,
    required String message,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/chat');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'session_id': sessionId, // Links this chat to the existing Vertex AI session
        'message': message,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      // Return the reply string, defaulting to empty string if null
      return data['reply'] as String? ?? '';
    } else {
      // Surface the full response body to help with debugging failed requests
      throw Exception(
        'API Error ${response.statusCode}: ${response.body}',
      );
    }
  }

  /// Sends analysis request with geospatial data and writes results
  /// back to Firestore via the backend.
  ///
  /// [projectId] identifies the Firestore document to update.
  /// [boundaryPoints] are the AOI coordinates drawn on the map.
  // Calls the heavy /api/analyze endpoint — runs the full 5-agent pipeline.
  // Typical response time: ~150–165 seconds (~2.5 minutes).
  // Returns a Dart record containing both the Markdown report and the
  // structured planting grid dict from the Plotter agent.
  Future<({String reply, Map<String, dynamic>? plantingGrid})> analyze({
    required String sessionId,
    required String projectId,
    required String message,
    required List<LatLng> boundaryPoints,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/analyze');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'session_id': sessionId,   // Links this analysis to the project's Vertex AI session
        'project_id': projectId,   // Firestore document ID to update after analysis
        'message': message,        // Enriched message with System Context prepended
        // Serialize each LatLng point to {latitude, longitude} for the backend
        'boundary_points': boundaryPoints
            .map((p) => {
                  'latitude': p.latitude,
                  'longitude': p.longitude,
                })
            .toList(),
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      // Safely cast the planting grid to Map<String, dynamic> if present
      // Returns null if the Plotter did not generate a grid (e.g. pipeline error)
      final grid = data['plantingGrid'] is Map
          ? Map<String, dynamic>.from(data['plantingGrid'])
          : null;
      // Return both the Markdown report and the planting grid as a named record
      return (reply: data['reply'] as String? ?? '', plantingGrid: grid);
    } else {
      // Surface the full response body to help with debugging failed requests
      throw Exception(
        'API Error ${response.statusCode}: ${response.body}',
      );
    }
  }
}