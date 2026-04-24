import 'package:flutter/material.dart';

// Riverpod for watching the real-time project list stream from Firestore
import 'package:flutter_riverpod/flutter_riverpod.dart';

// go_router for navigating to the project screen after creation
import 'package:go_router/go_router.dart';

// Inter font used throughout the dashboard
import 'package:google_fonts/google_fonts.dart';

// Date formatting for the "Created on" label on each project card
import 'package:intl/intl.dart';

import '../theme.dart';
import '../models/project.dart';          // Project data model with Firestore mapping
import '../providers/app_providers.dart'; // projectListProvider and projectServiceProvider
import '../widgets/app_top_bar.dart';     // 64px glassmorphic top navigation bar
import '../widgets/glass_card.dart';      // Reusable glassmorphic card widget

/// Dashboard page showing the user's projects.
// ConsumerWidget so it can watch the real-time Firestore project stream
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the real-time Firestore stream — rebuilds on every project change
    final projectsAsync = ref.watch(projectListProvider);

    return Scaffold(
      extendBodyBehindAppBar: true, // Content extends behind the transparent app bar
      appBar: const AppTopBar(showDashboardButton: false), // Hide the dashboard button on this screen
      body: Padding(
        padding: const EdgeInsets.only(top: 64), // Offset for the 64px app bar height
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Switch between wide (desktop) and narrow (mobile) layouts at 800px
            final isWide = constraints.maxWidth > 800;
            final horizontalPadding = isWide ? 80.0 : 24.0;

            return projectsAsync.when(
              // Show a centered spinner while the Firestore stream is loading
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppTheme.accent),
              ),
              // Show an error message if the Firestore stream fails
              error: (err, stack) => Center(
                child: Text(
                  'Error loading projects: $err',
                  style: GoogleFonts.inter(color: AppTheme.error),
                ),
              ),
              data: (projects) => SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: 40,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row — title + project count on the left, New Project button on the right
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Active Projects',
                                style: GoogleFonts.inter(
                                  fontSize: isWide ? 32 : 24,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Pluralise "project" correctly based on count
                              Text(
                                '${projects.length} project${projects.length == 1 ? '' : 's'}',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // New Project button — opens the create project dialog
                        ElevatedButton.icon(
                          onPressed: () => _showNewProjectDialog(context, ref),
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: const Text('New Project'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),

                    // Project grid or empty state depending on whether projects exist
                    if (projects.isEmpty)
                      // Empty state — dashed card prompting the user to create their first project
                      _EmptyState(
                        onTap: () => _showNewProjectDialog(context, ref),
                      )
                    else
                      // Responsive grid: 3 columns on wide desktop, 2 on tablet, 1 on mobile
                      _ProjectGrid(
                        projects: projects,
                        crossAxisCount:
                            constraints.maxWidth > 1100 ? 3 : (isWide ? 2 : 1),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // Shows a dialog for creating a new project with name and description fields
  void _showNewProjectDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Create New Project',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: 400, // Fixed dialog width for consistent appearance
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Project name — required field (validated before creation)
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Project Name',
                  hintText: 'e.g. Sabah Agroforestry Site',
                ),
              ),
              const SizedBox(height: 16),
              // Project description — optional multi-line field
              TextField(
                controller: descController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Brief description of the site or analysis goal',
                ),
              ),
            ],
          ),
        ),
        actions: [
          // Cancel — closes the dialog without creating a project
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          // Create & Analyze — writes the project to Firestore then navigates to it
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return; // Guard: name is required
              final service = ref.read(projectServiceProvider);
              final project = await service.addProject(
                name: name,
                description: descController.text.trim(),
              );
              if (ctx.mounted) Navigator.pop(ctx);
              // Navigate directly to the new project's analysis screen
              if (context.mounted) context.go('/project/${project.id}');
            },
            child: const Text('Create & Analyze'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty State
// ---------------------------------------------------------------------------
// Shown when the user has no projects — a dashed interactive card that opens
// the new project dialog when tapped or hovered
class _EmptyState extends StatefulWidget {
  final VoidCallback onTap;

  const _EmptyState({required this.onTap});

  @override
  State<_EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<_EmptyState> {
  // Tracks mouse hover state to animate the card border and icon color
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: MouseRegion(
        // Update hover state on mouse enter/exit to trigger the animation
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap, // Tap anywhere on the card to open the dialog
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200), // Smooth 200ms hover animation
            width: 400,
            height: 240,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                // Accent border on hover, muted border at rest
                color: _hovering
                    ? AppTheme.accent.withValues(alpha: 0.6)
                    : AppTheme.textSecondary.withValues(alpha: 0.3),
                width: 2,
              ),
              // Subtle accent background tint on hover
              color: _hovering
                  ? AppTheme.accent.withValues(alpha: 0.05)
                  : Colors.transparent,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Plus icon — changes to accent color on hover
                Icon(
                  Icons.add_circle_outline_rounded,
                  size: 56,
                  color: _hovering ? AppTheme.accent : AppTheme.textSecondary,
                ),
                const SizedBox(height: 16),
                // Primary label — changes to accent color on hover
                Text(
                  'Create your first project',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color:
                        _hovering ? AppTheme.accent : AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                // Secondary label — muted hint text
                Text(
                  'Start an agroforestry analysis',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppTheme.textSecondary.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Project Grid
// ---------------------------------------------------------------------------
// Renders all projects as a responsive grid of glassmorphic cards
// ConsumerWidget so it can access projectServiceProvider for delete operations
class _ProjectGrid extends ConsumerWidget {
  final List<Project> projects;
  final int crossAxisCount; // Number of columns — passed in from the parent layout

  const _ProjectGrid({
    required this.projects,
    required this.crossAxisCount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(), // Parent SingleChildScrollView handles scrolling
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 20,
        crossAxisSpacing: 20,
        childAspectRatio: 1.8, // Wider than tall — suits a card with title + description
      ),
      itemCount: projects.length,
      itemBuilder: (context, index) {
        final project = projects[index];
        // Each project rendered as a tappable glassmorphic card
        return GlassCard(
          onTap: () => context.go('/project/${project.id}'), // Navigate to the project screen
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Project icon — gradient background with a forest icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.accent.withValues(alpha: 0.2),
                          AppTheme.success.withValues(alpha: 0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.forest_rounded,
                      color: AppTheme.accentLight,
                      size: 22,
                    ),
                  ),
                  const Spacer(),
                  // Delete button — muted icon that triggers the confirmation dialog
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: AppTheme.textSecondary.withValues(alpha: 0.6),
                      size: 20,
                    ),
                    onPressed: () => _confirmDelete(context, ref, project),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Project name — truncated to one line with ellipsis
              Text(
                project.name,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // Project description — truncated to two lines with ellipsis
              // Falls back to "No description" if empty
              Text(
                project.description.isNotEmpty
                    ? project.description
                    : 'No description',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              // Creation date — formatted as "Jan 1, 2026" at the bottom of the card
              Text(
                'Created ${DateFormat.yMMMd().format(project.createdAt)}',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppTheme.textSecondary.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Shows a confirmation dialog before permanently deleting a project from Firestore
  void _confirmDelete(BuildContext context, WidgetRef ref, dynamic project) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete Project',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        // Warn the user that deletion is irreversible
        content: Text(
          'Are you sure you want to delete "${project.name}"? This action cannot be undone.',
          style: GoogleFonts.inter(color: AppTheme.textSecondary),
        ),
        actions: [
          // Cancel — closes the dialog without deleting
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          // Delete — red button to signal a destructive action
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error, // Red background for destructive action
            ),
            onPressed: () async {
              final service = ref.read(projectServiceProvider);
              // Delete the project document from Firestore
              await service.deleteProject(project.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}