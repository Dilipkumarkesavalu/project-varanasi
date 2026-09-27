import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'v_button.dart';

/// Shown while data loads.
class LoadingView extends StatelessWidget {
  const LoadingView({this.message, super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return _Centered(
      children: [
        const CircularProgressIndicator(),
        if (message != null) ...[
          const SizedBox(height: VSpacing.lg),
          Text(message!, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    );
  }
}

/// Shown when a list or page has no data.
class EmptyView extends StatelessWidget {
  const EmptyView({required this.title, this.message, this.action, super.key});

  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return _Centered(
      children: [
        const Icon(Icons.inbox_outlined, size: 48, color: VColors.textDisabled),
        const SizedBox(height: VSpacing.md),
        Text(title, style: textTheme.titleMedium, textAlign: TextAlign.center),
        if (message != null) ...[
          const SizedBox(height: VSpacing.xs),
          Text(
            message!,
            style: textTheme.bodyMedium?.copyWith(color: VColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
        if (action != null) ...[const SizedBox(height: VSpacing.lg), action!],
      ],
    );
  }
}

/// Shown when loading failed. Shows the correlation ID so support can find the logs.
class ErrorView extends StatelessWidget {
  const ErrorView({
    required this.title,
    this.message,
    this.correlationId,
    this.onRetry,
    super.key,
  });

  final String title;
  final String? message;
  final String? correlationId;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return _Centered(
      children: [
        const Icon(Icons.error_outline, size: 48, color: VColors.danger),
        const SizedBox(height: VSpacing.md),
        Text(title, style: textTheme.titleMedium, textAlign: TextAlign.center),
        if (message != null) ...[
          const SizedBox(height: VSpacing.xs),
          Text(
            message!,
            style: textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
        if (correlationId != null) ...[
          const SizedBox(height: VSpacing.sm),
          SelectableText(
            'Reference: $correlationId',
            style: textTheme.bodySmall?.copyWith(color: VColors.textSecondary),
          ),
        ],
        if (onRetry != null) ...[
          const SizedBox(height: VSpacing.lg),
          VButton(
            label: 'Try again',
            icon: Icons.refresh,
            variant: VButtonVariant.secondary,
            onPressed: onRetry,
          ),
        ],
      ],
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(VSpacing.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}
