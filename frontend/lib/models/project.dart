import 'package:cloud_firestore/cloud_firestore.dart';

/// Data model for an AgroMind project.
class Project {
  final String id;
  final String name;
  final String description;
  final DateTime createdAt;
  final String sessionId;
  final String? reportMarkdown;
  final List<Map<String, double>>? boundaryPoints;
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
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'createdAt': Timestamp.fromDate(createdAt),
      'sessionId': sessionId,
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
      description: map['description'] as String? ?? '',
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      sessionId: map['sessionId'] as String,
      reportMarkdown: map['reportMarkdown'] as String?,
      boundaryPoints: (map['boundaryPoints'] as List<dynamic>?)
          ?.map((item) => Map<String, double>.from(item as Map))
          .toList(),
      plantingGrid: map['plantingGrid'] is Map
          ? Map<String, dynamic>.from(map['plantingGrid'])
          : null,
    );
  }

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
