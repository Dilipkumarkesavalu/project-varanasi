import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum VButtonVariant { primary, secondary, danger, text }

/// The standard button. While [loading] it shows a spinner and ignores taps,
/// which prevents double submissions.
class VButton extends StatelessWidget {
  const VButton({
    required this.label,
    required this.onPressed,
    this.variant = VButtonVariant.primary,
    this.icon,
    this.loading = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final VButtonVariant variant;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final onTap = loading ? null : onPressed;
    final child = loading
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: VSpacing.sm),
              ],
              Text(label),
            ],
          );
    const padding = EdgeInsets.symmetric(
      horizontal: VSpacing.lg,
      vertical: VSpacing.md,
    );
    const shape = RoundedRectangleBorder(borderRadius: VRadius.mdAll);

    return Semantics(
      button: true,
      label: label,
      child: switch (variant) {
        VButtonVariant.primary => FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(padding: padding, shape: shape),
          child: child,
        ),
        VButtonVariant.danger => FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            padding: padding,
            shape: shape,
            backgroundColor: VColors.danger,
          ),
          child: child,
        ),
        VButtonVariant.secondary => OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(padding: padding, shape: shape),
          child: child,
        ),
        VButtonVariant.text => TextButton(onPressed: onTap, child: child),
      },
    );
  }
}
