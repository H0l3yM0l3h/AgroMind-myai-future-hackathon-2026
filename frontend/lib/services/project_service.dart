// Firestore client for real-time database operations
import 'package:cloud_firestore/cloud_firestore.dart';

// UUID generator for creating unique project and session IDs
import 'package:uuid/uuid.dart';

import '../models/project.dart'; // Project data model with toMap/fromMap serialization

/// Service class for CRUD operations on the Firestore `projects` collection.
class ProjectService {
  // Single Firestore instance shared across all operations in this service
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Static UUID generator — const so it's shared across all ProjectService instances
  static const _uuid = Uuid();

  /// Reference to the top-level `projects` collection.
  // Typed as Map<String, dynamic> to match the Project.toMap() / fromMap() format
  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('projects');

  /// Returns a real-time stream of all projects, ordered by creation date
  /// (newest first).
  // The stream automatically emits a new list whenever a project is added,
  // updated, or deleted — no manual refresh needed in the UI
  Stream<List<Project>> streamProjects() {
    return _collection
        .orderBy('createdAt', descending: true) // Newest projects appear first
        .snapshots()                             // Real-time Firestore snapshot stream
        .map((snapshot) =>
            // Convert each Firestore document to a Project model
            snapshot.docs.map((doc) => Project.fromMap(doc.data())).toList());
  }

  /// Creates a new project document in Firestore and returns the [Project].
  Future<Project> addProject({
    required String name,
    required String description,
  }) async {
    final project = Project(
      id: _uuid.v4(),          // Unique document ID — also used as the URL path parameter
      name: name,
      description: description,
      createdAt: DateTime.now(),
      sessionId: _uuid.v4(),   // Separate UUID for the Vertex AI session — one per project
    );

    // Use the project's UUID as the document ID for easy lookups.
    // This avoids needing a separate query to find a project by ID
    await _collection.doc(project.id).set(project.toMap());
    return project; // Return the local Project object so the UI can navigate immediately
  }

  /// Deletes a project document by its [id].
  // Permanently removes the Firestore document — this action cannot be undone
  // The UI shows a confirmation dialog before calling this method
  Future<void> deleteProject(String id) async {
    await _collection.doc(id).delete();
  }
}