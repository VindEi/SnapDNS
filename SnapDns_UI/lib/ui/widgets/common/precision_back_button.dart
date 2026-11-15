import 'package:flutter/material.dart';

class PrecisionBackButton extends StatefulWidget {
  final VoidCallback onTap;
  const PrecisionBackButton({super.key, required this.onTap});

  @override
  State<PrecisionBackButton> createState() => _PrecisionBackButtonState();
}

class _PrecisionBackButtonState extends State<PrecisionBackButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _isHovered
                ? colorScheme.onSurface.withValues(alpha: 0.05)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 14,
            color: _isHovered
                ? colorScheme.onSurface
                : colorScheme.onSurface.withValues(alpha: 0.2),
          ),
        ),
      ),
    );
  }
}
