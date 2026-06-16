import 'package:flutter/material.dart';

class ActionButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final Color backgroundColor;
  final Color textColor;
  final bool outlined;

  const ActionButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.backgroundColor,
    required this.textColor,
    this.outlined = false,
  });

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (mounted) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _isHovered = false);
      },
      child: GestureDetector(
        onTapDown: (_) {
          if (mounted) setState(() => _isPressed = true);
        },
        onTapUp: (_) {
          if (mounted) setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () {
          if (mounted) setState(() => _isPressed = false);
        },
        child: AnimatedScale(
          duration: const Duration(milliseconds: 40),
          scale: _isPressed ? 0.96 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.backgroundColor,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _isHovered
                    ? widget.backgroundColor.withValues(alpha: 0.4)
                    : (widget.outlined
                        ? colorScheme.outline.withValues(alpha: 0.1)
                        : Colors.transparent),
                width: 1,
              ),
              boxShadow: [
                if (_isHovered && !widget.outlined)
                  BoxShadow(
                    color: widget.backgroundColor.withValues(alpha: 0.15),
                    blurRadius: 12,
                  ),
              ],
            ),
            child: Text(
              widget.label.toUpperCase(),
              style: TextStyle(
                color: widget.textColor,
                fontWeight: FontWeight.w900,
                fontSize: 11,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
