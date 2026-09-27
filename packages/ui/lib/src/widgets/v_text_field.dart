import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Labelled form field with helper and error text.
///
/// Pass [errorText] to show a server-side validation error (e.g. from a `422`
/// field error); [validator] runs inside a [Form].
class VTextField extends StatelessWidget {
  const VTextField({
    required this.label,
    this.controller,
    this.hint,
    this.helperText,
    this.errorText,
    this.validator,
    this.onChanged,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
    this.required = false,
    super.key,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helperText;
  final String? errorText;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool enabled;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          required ? '$label *' : label,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: VSpacing.xs),
        TextFormField(
          controller: controller,
          validator:
              validator ??
              (required
                  ? (value) => (value == null || value.trim().isEmpty)
                        ? '$label is required.'
                        : null
                  : null),
          onChanged: onChanged,
          keyboardType: keyboardType,
          obscureText: obscureText,
          enabled: enabled,
          decoration: InputDecoration(
            hintText: hint,
            helperText: helperText,
            errorText: errorText,
          ),
        ),
      ],
    );
  }
}
