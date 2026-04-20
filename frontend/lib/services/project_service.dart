import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../models/project.dart';

/// Service class for CRUD operations on the Firestore `projects` collection.
class ProjectService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const _uuid = Uuid();

  /// Reference to the top-level `projects` collection.
  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('projects');

  /// Returns a real-time stream of all projects, ordered by creation date
  /// (newest first).
  Stream<List<Project>> streamProjects() {
    return _collection
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Project.fromMap(doc.data())).toList());
  }

  /// Creates a new project document in Firestore and returns the [Project].
  Future<Project> addProject({
    required String name,
    required String description,
  }) async {
    final project = Project(
      id: _uuid.v4(),
      name: name,
      description: description,
      createdAt: DateTime.now(),
      sessionId: _uuid.v4(),
    );

    // Use the project's UUID as the document ID for easy lookups.
    await _collection.doc(project.id).set(project.toMap());
    return project;
  }

  /// Deletes a project document by its [id].
  Future<void> deleteProject(String id) async {
    await _collection.doc(id).delete();
  }
}
