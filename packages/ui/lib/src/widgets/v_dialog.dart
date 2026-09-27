import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'v_button.dart';

/// Shows a standard dialog with a title, body and actions.
Future<T?> showVDialog<T>({
  required BuildContext context,
  required String title,
  required Widget body,
  List<Widget> actions = const [],
}) {
  return showDialog<T>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: body,
      ),
      actionsPadding: const EdgeInsets.all(VSpacing.lg),
      actions: actions,
    ),
  );
}

/// Asks the user to confirm. Returns `true` only when they confirm.
///
/// Use [destructive] for irreversible actions (void an invoice, terminate an employee).
Future<bool> showVConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final confirmed = await showVDialog<bool>(
    context: context,
    title: title,
    body: Text(message),
    actions: [
      Builder(
        builder: (context) => VButton(
          label: cancelLabel,
          variant: VButtonVariant.text,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      Builder(
        builder: (context) => VButton(
          label: confirmLabel,
          variant: destructive ? VButtonVariant.danger : VButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ),
    ],
  );
  return confirmed ?? false;
}
