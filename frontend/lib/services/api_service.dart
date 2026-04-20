import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/lat_lng.dart';

/// Service class for communicating with the AgroMind FastAPI backend.
class ApiService {
  // Change this to your deployed backend URL in production.
  static const String _baseUrl = 'http://localhost:8000';

  /// Sends a chat message to the orchestrator and returns the reply.
  ///
  /// [sessionId] ties the request to a persistent conversation session.
  /// [message] is the user's natural-language query.
  Future<String> chat({
    required String sessionId,
    required String message,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/chat');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'session_id': sessionId,
        'message': message,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['reply'] as String? ?? '';
    } else {
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
        'session_id': sessionId,
        'project_id': projectId,
        'message': message,
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
      final grid = data['plantingGrid'] is Map
          ? Map<String, dynamic>.from(data['plantingGrid'])
          : null;
      return (reply: data['reply'] as String? ?? '', plantingGrid: grid);
    } else {
      throw Exception(
        'API Error ${response.statusCode}: ${response.body}',
      );
    }
  }
}
