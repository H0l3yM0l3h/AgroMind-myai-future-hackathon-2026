// Firestore Timestamp for converting between DateTime and Firestore's date format
import 'package:cloud_firestore/cloud_firestore.dart';

/// Data model for an AgroMind project.
class Project {
  // Firestore document ID — also used as the URL path parameter in /project/:id
  final String id;

  // User-provided project name shown on the dashboard card and command center header
  final String name;

  // Optional user-provided description shown on the dashboard card
  final String description;

  // When the project was created — used for ordering in the dashboard (newest first)
  final DateTime createdAt;

  // Separate UUID from id — ties this project to a specific Vertex AI session
  // so the chat agent and analysis pipeline share the same conversation history
  final String sessionId;

  // AI-generated Markdown business plan written by the Documentarian agent
  // Null until the first analysis has been completed and persisted by the backend
  final String? reportMarkdown;

  // Farm boundary coordinates drawn on the map — persisted by the backend after analysis
  // Each point is {latitude: double, longitude: double}
  // Null until the first analysis has been completed
  final List<Map<String, double>>? boundaryPoints;

  // Computed planting grid from the Plotter agent — contains timber and intercrop
  // GPS positions rendered as Circle overlays on the Flutter map
  // Null until the Plotter has successfully generated a grid
  final Map<String, dynamic>? plantingGrid;

  Project({
    required this.id,
    required this.name,
    required this.description,
    required this.createdAt,
    required this.sessionId,
    this.reportMarkdown,
    this.boundaryPoints,
    this.plantingGrid,
  });

  /// Serialise this project into a Firestore-compatible map.
  // Optional fields are only included when non-null to avoid storing
  // explicit null values in Firestore documents
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      // Convert DateTime to Firestore Timestamp for correct date storage and ordering
      'createdAt': Timestamp.fromDate(createdAt),
      'sessionId': sessionId,
      // Conditionally include optional fields only when they have values
      if (reportMarkdown != null) 'reportMarkdown': reportMarkdown,
      if (boundaryPoints != null) 'boundaryPoints': boundaryPoints,
      if (plantingGrid != null) 'plantingGrid': plantingGrid,
    };
  }

  /// Deserialise a Firestore document snapshot into a [Project].
  factory Project.fromMap(Map<String, dynamic> map) {
    return Project(
      id: map['id'] as String,
      name: map['name'] as String,
      // Default to empty string if description is missing from older documents
      description: map['description'] as String? ?? '',
      // Convert Firestore Timestamp back to Dart DateTime
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      sessionId: map['sessionId'] as String,
      reportMarkdown: map['reportMarkdown'] as String?,
      // Defensively cast each boundary point from dynamic to Map<String, double>
      boundaryPoints: (map['boundaryPoints'] as List<dynamic>?)
          ?.map((item) => Map<String, double>.from(item as Map))
          .toList(),
      // Guard against Firestore returning a non-Map type for plantingGrid
      plantingGrid: map['plantingGrid'] is Map
          ? Map<String, dynamic>.from(map['plantingGrid'])
          : null,
    );
  }

  // Returns a new Project with the specified fields replaced — all other fields
  // carry over from the original. Used when updating a project in memory without
  // writing the full document back to Firestore.
  Project copyWith({
    String? id,
    String? name,
    String? description,
    DateTime? createdAt,
    String? sessionId,
    String? reportMarkdown,
    List<Map<String, double>>? boundaryPoints,
    Map<String, dynamic>? plantingGrid,
  }) {
    return Project(
      // Use the provided value if non-null, otherwise fall back to the current value
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      sessionId: sessionId ?? this.sessionId,
      reportMarkdown: reportMarkdown ?? this.reportMarkdown,
      boundaryPoints: boundaryPoints ?? this.boundaryPoints,
      plantingGrid: plantingGrid ?? this.plantingGrid,
    );
  }
}