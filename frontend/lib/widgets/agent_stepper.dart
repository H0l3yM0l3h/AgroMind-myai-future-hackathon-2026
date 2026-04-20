import 'package:flutter/material.dart';

import '../models/agent_step.dart';
import '../theme.dart';

/// A visual stepper showing the status of the 5 sub-agent pipeline steps.
class AgentStepper extends StatelessWidget {
  /// The currently active step. Steps before it are complete, steps after are pending.
  final AgentStep? currentStep;

  const AgentStepper({super.key, this.currentStep});

  @override
  Widget build(BuildContext context) {
    final steps = AgentStep.values;
    final activeIndex =
        currentStep != null ? steps.indexOf(currentStep!) : -1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          _StepTile(
            step: steps[i],
            status: activeIndex < 0
                ? _StepStatus.pending
                : i < activeIndex
                    ? _StepStatus.complete
                    : i == activeIndex
                        ? _StepStatus.active
                        : _StepStatus.pending,
          ),
          if (i < steps.length - 1)
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Container(
                width: 2,
                height: 24,
                color: i < activeIndex
                    ? AppTheme.success
                    : AppTheme.border,
              ),
            ),
        ],
      ],
    );
  }
}

enum _StepStatus { pending, active, complete }

class _StepTile extends StatelessWidget {
  final AgentStep step;
  final _StepStatus status;

  const _StepTile({required this.step, required this.status});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Step indicator circle
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: switch (status) {
              _StepStatus.complete => AppTheme.success,
              _StepStatus.active => AppTheme.accent,
              _StepStatus.pending =>
                AppTheme.surfaceLight.withValues(alpha: 0.5),
            },
            boxShadow: status == _StepStatus.active
                ? [
                    BoxShadow(
                      color: AppTheme.accent.withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 2,
                    )
                  ]
                : null,
          ),
          child: Center(
            child: switch (status) {
              _StepStatus.complete => const Icon(
                  Icons.check_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              _StepStatus.active => const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              _StepStatus.pending => Icon(
                  Icons.circle_outlined,
                  size: 18,
                  color: AppTheme.textSecondary.withValues(alpha: 0.5),
                ),
            },
          ),
        ),
        const SizedBox(width: 16),
        // Step label and subtitle
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: status == _StepStatus.pending
                      ? AppTheme.textSecondary
                      : AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                step.subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: status == _StepStatus.active
                      ? AppTheme.accentLight
                      : AppTheme.textSecondary.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
