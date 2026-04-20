import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../theme.dart';
import '../models/project.dart';
import '../providers/app_providers.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/glass_card.dart';

/// Dashboard page showing the user's projects.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectListProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppTopBar(showDashboardButton: false),
      body: Padding(
        padding: const EdgeInsets.only(top: 64),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 800;
            final horizontalPadding = isWide ? 80.0 : 24.0;

            return projectsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppTheme.accent),
              ),
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
                    // Header row
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
                        ElevatedButton.icon(
                          onPressed: () => _showNewProjectDialog(context, ref),
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: const Text('New Project'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),

                    // Project grid or empty state
                    if (projects.isEmpty)
                      _EmptyState(
                        onTap: () => _showNewProjectDialog(context, ref),
                      )
                    else
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
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Project Name',
                  hintText: 'e.g. Sabah Agroforestry Site',
                ),
              ),
              const SizedBox(height: 16),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final service = ref.read(projectServiceProvider);
              final project = await service.addProject(
                name: name,
                description: descController.text.trim(),
              );
              if (ctx.mounted) Navigator.pop(ctx);
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
class _EmptyState extends StatefulWidget {
  final VoidCallback onTap;

  const _EmptyState({required this.onTap});

  @override
  State<_EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<_EmptyState> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 400,
            height: 240,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _hovering
                    ? AppTheme.accent.withValues(alpha: 0.6)
                    : AppTheme.textSecondary.withValues(alpha: 0.3),
                width: 2,
              ),
              color: _hovering
                  ? AppTheme.accent.withValues(alpha: 0.05)
                  : Colors.transparent,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_circle_outline_rounded,
                  size: 56,
                  color: _hovering ? AppTheme.accent : AppTheme.textSecondary,
                ),
                const SizedBox(height: 16),
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
class _ProjectGrid extends ConsumerWidget {
  final List<Project> projects;
  final int crossAxisCount;

  const _ProjectGrid({
    required this.projects,
    required this.crossAxisCount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 20,
        crossAxisSpacing: 20,
        childAspectRatio: 1.8,
      ),
      itemCount: projects.length,
      itemBuilder: (context, index) {
        final project = projects[index];
        return GlassCard(
          onTap: () => context.go('/project/${project.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
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

  void _confirmDelete(BuildContext context, WidgetRef ref, dynamic project) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete Project',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Are you sure you want to delete "${project.name}"? This action cannot be undone.',
          style: GoogleFonts.inter(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
            ),
            onPressed: () async {
              final service = ref.read(projectServiceProvider);
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
