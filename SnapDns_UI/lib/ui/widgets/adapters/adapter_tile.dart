import 'package:flutter/material.dart';

class AdapterTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const AdapterTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<AdapterTile> createState() => _AdapterTileState();
}

class _AdapterTileState extends State<AdapterTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.primary;

    IconData iconData = Icons.lan_outlined;
    if (widget.title.toLowerCase().contains("wi-fi") ||
        widget.title.toLowerCase().contains("wlan")) {
      iconData = Icons.wifi_rounded;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (mounted) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _isHovered = false);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? accent.withValues(alpha: 0.05)
                : (_isHovered
                    ? colorScheme.onSurface.withValues(alpha: 0.015)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: widget.isSelected
                  ? accent
                  : (_isHovered
                      ? colorScheme.onSurface.withValues(alpha: 0.1)
                      : colorScheme.outline.withValues(alpha: 0.05)),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                iconData,
                size: 18,
                color: widget.isSelected
                    ? accent
                    : colorScheme.onSurface.withValues(alpha: 0.2),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: widget.isSelected
                            ? accent
                            : colorScheme.onSurface.withValues(alpha: 0.8),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.onSurface.withValues(alpha: 0.2),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.isSelected)
                Icon(Icons.check_circle_rounded, size: 16, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}
