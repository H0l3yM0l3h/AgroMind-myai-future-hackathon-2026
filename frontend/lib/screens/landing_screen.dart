import 'dart:ui';
import 'package:flutter/material.dart';

// go_router for navigation — context.go('/dashboard') navigates to the dashboard
import 'package:go_router/go_router.dart';

// Inter font for all text throughout the landing screen
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';
import '../widgets/app_top_bar.dart';  // 64px glassmorphic top navigation bar
import '../widgets/glass_card.dart';   // Reusable glassmorphic card widget

/// The landing / hero page at route "/".
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, // Hero section extends behind the transparent app bar
      appBar: const AppTopBar(showDashboardButton: true),
      body: Stack(
        children: [
          // Background gradient orbs — decorative blurred circles behind the content
          _BackgroundOrbs(),
          // Main content — scrollable column of hero, features, and footer sections
          SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 64), // appbar offset
                _HeroSection(),
                const SizedBox(height: 80),
                _FeaturesSection(),
                const SizedBox(height: 80),
                _FooterSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Background decorative orbs
// ---------------------------------------------------------------------------
// Two large radial gradient circles positioned off-screen corners to create
// a subtle ambient glow effect behind the page content
class _BackgroundOrbs extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Top-right orb — accent blue glow
        Positioned(
          top: -120,
          right: -120,
          child: Container(
            width: 400,
            height: 400,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppTheme.accent.withValues(alpha: 0.15), // 15% accent blue at center
                  Colors.transparent,                       // Fades to transparent
                ],
              ),
            ),
          ),
        ),
        // Bottom-left orb — success green glow
        Positioned(
          bottom: -80,
          left: -80,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppTheme.success.withValues(alpha: 0.08), // 8% green at center
                  Colors.transparent,                        // Fades to transparent
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero Section
// ---------------------------------------------------------------------------
// The primary above-the-fold section — badge, headline, subtitle, and CTA button
class _HeroSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive layout: wider padding and larger text on desktop
        final isWide = constraints.maxWidth > 800;
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 80 : 24, // More horizontal padding on desktop
            vertical: 80,
          ),
          child: Column(
            children: [
              // Badge — small pill above the headline indicating the hackathon context
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(100), // Fully rounded pill shape
                  border: Border.all(
                    color: AppTheme.accent.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Green dot indicating "live" / active status
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.success,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Project 2030: MyAI Future',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.accentLight,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Headline — main value proposition in large bold text
              Text(
                'Screening-level land\nfeasibility, powered by AI',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: isWide ? 56 : 36, // Larger on desktop, smaller on mobile
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                  height: 1.1,
                  letterSpacing: -1.5, // Tight tracking for a modern display style
                ),
              ),
              const SizedBox(height: 24),

              // Subtitle — one-sentence product description
              SizedBox(
                width: isWide ? 600 : double.infinity, // Constrained width on desktop
                child: Text(
                  'AgroMind uses a multi-agent AI system to analyze land, recommend crops, calculate ROI, and generate agroforestry business plans — all from a single prompt.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: isWide ? 18 : 15,
                    color: AppTheme.textSecondary,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // CTA button — navigates to the dashboard to create a new project
              ElevatedButton.icon(
                onPressed: () => context.go('/dashboard'),
                icon: const Icon(Icons.rocket_launch_rounded, size: 20),
                label: const Text('Get Started'),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                  textStyle: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Features Section – 4 glassmorphic cards
// ---------------------------------------------------------------------------
// Showcases the 4 key capabilities of AgroMind in a responsive grid layout
class _FeaturesSection extends StatelessWidget {
  // Static list of feature data — defined at class level to avoid rebuilding on each render
  static const _features = [
    _Feature(
      icon: Icons.public_rounded,
      title: '3D Site Context',
      description:
          'Geospatial land analysis with terrain and soil profiling for precise site assessment.',
    ),
    _Feature(
      icon: Icons.layers_rounded,
      title: 'Multi-layer Environmental Analysis',
      description:
          'Climate, rainfall, and soil chemistry data synthesized across multiple data layers.',
    ),
    _Feature(
      icon: Icons.insights_rounded,
      title: 'Socioeconomic Intelligence',
      description:
          '15-year ROI projections, cost analysis, and market-aware crop recommendations.',
    ),
    _Feature(
      icon: Icons.description_rounded,
      title: 'AI-Synthesized Reports',
      description:
          'Professional agroforestry business plans compiled automatically by AI agents.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;
        // Responsive column count: 4 on desktop, 2 on tablet, 1 on mobile
        final crossAxisCount = isWide ? 4 : (constraints.maxWidth > 600 ? 2 : 1);
        final horizontalPadding = isWide ? 80.0 : 24.0;

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Column(
            children: [
              // Section heading
              Text(
                'Intelligent Analysis Pipeline',
                style: GoogleFonts.inter(
                  fontSize: isWide ? 32 : 24,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              // Section subtitle
              Text(
                'Five specialist AI agents working in sequence to deliver comprehensive land assessments.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 48),

              // Responsive feature card grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(), // Parent handles scrolling
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 20,
                  childAspectRatio: isWide ? 0.95 : 1.6, // Taller cards on desktop
                ),
                itemCount: _features.length,
                itemBuilder: (context, index) {
                  final feature = _features[index];
                  // Each feature rendered as a glassmorphic card with icon, title, description
                  return GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Icon container with gradient background
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppTheme.accent.withValues(alpha: 0.2),
                                AppTheme.accent.withValues(alpha: 0.05),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            feature.icon,
                            color: AppTheme.accentLight,
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Feature title
                        Text(
                          feature.title,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Feature description
                        Text(
                          feature.description,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// Data class for a single feature card — icon, title, and description
class _Feature {
  final IconData icon;
  final String title;
  final String description;

  const _Feature({
    required this.icon,
    required this.title,
    required this.description,
  });
}

// ---------------------------------------------------------------------------
// Footer
// ---------------------------------------------------------------------------
// Simple footer with copyright notice and disclaimer — sits below the features section
class _FooterSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        // Subtle top border to visually separate the footer from the features section
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Column(
        children: [
          // Copyright line
          Text(
            '© 2026 AgroMind. All rights reserved.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          // Disclaimer — clarifies AgroMind is for screening-level analysis only
          Text(
            'AgroMind provides screening-level analysis for informational purposes only.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppTheme.textSecondary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}