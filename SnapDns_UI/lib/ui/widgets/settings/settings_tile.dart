import 'package:flutter/material.dart';

class SettingsSwitch extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isSubOption; // FIX: Added sub-option nesting support

  const SettingsSwitch({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.isSubOption = false, // Defaults to a standard root switch
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => onChanged(!value),
      mouseCursor: SystemMouseCursors.click,
      hoverColor: colorScheme.onSurface.withValues(alpha: 0.04),
      child: Padding(
        // FIX: Indent padding when configured as a sub-option to visually group it under its parent
        padding: EdgeInsets.only(
          left: isSubOption ? 32.0 : 16.0,
          right: 16.0,
          top: 12.0,
          bottom: 12.0,
        ),
        child: Row(
          children: [
            // FIX: Add a subtle vertical subdirectory arrow to visually link it to the parent toggle
            if (isSubOption) ...[
              Icon(
                Icons.subdirectory_arrow_right_rounded,
                size: 14,
                color: colorScheme.onSurface.withValues(alpha: 0.2),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: isSubOption
                          ? 12
                          : 13, // Slightly smaller font for sub-option hierarchy
                      fontWeight: FontWeight.bold,
                      color: isSubOption
                          ? colorScheme.onSurface.withValues(alpha: 0.8)
                          : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: isSubOption ? 10 : 11,
                      color: colorScheme.onSurface.withValues(alpha: 0.4),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            _PrecisionToggle(
              value: value,
              accent: colorScheme.primary,
              cs: colorScheme,
            ),
          ],
        ),
      ),
    );
  }
}

class _PrecisionToggle extends StatelessWidget {
  final bool value;
  final Color accent;
  final ColorScheme cs;
  const _PrecisionToggle({
    required this.value,
    required this.accent,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 32,
      height: 16,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: value
            ? accent.withValues(alpha: 0.15)
            : cs.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: value ? accent : cs.outline.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 150),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: value ? accent : cs.onSurface.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
