import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Modern, consistent dropdown used across the app: expanded, filled, rounded.
class AppDropdown<T> extends StatelessWidget {
  final String? label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final bool enabled;
  final String? hint;

  const AppDropdown({
    super.key,
    this.label,
    this.value,
    required this.items,
    this.onChanged,
    this.enabled = true,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      items: items,
      onChanged: enabled ? onChanged : null,
    );
  }
}

/// Consistent modal dialog: fixed max width, scrollable body, optional icon.
class AppModal extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget child;
  final List<Widget> actions;
  final double width;

  const AppModal({
    super.key,
    required this.title,
    this.icon,
    required this.child,
    required this.actions,
    this.width = 520,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 22, color: AppColors.primary),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(title,
                style: const TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      content: SizedBox(
        width: width,
        child: SingleChildScrollView(child: child),
      ),
      actions: actions,
    );
  }
}

/// A consistent "primary" filled button used in modal actions.
class AppModalButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  const AppModalButton({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(label),
    );
  }
}