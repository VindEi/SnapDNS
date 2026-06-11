import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import '../../../providers/dns_provider.dart';
import '../../../providers/settings_provider.dart';
import 'dynamic_icon.dart';

class CustomTitleBar extends StatelessWidget {
  const CustomTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final dns = context.watch<DnsProvider>();
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final settings = context.read<SettingsProvider>();
    final bool isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    // The core brand header (Logo + Name + Status Dot)
    final brandHeader = Container(
      padding: const EdgeInsets.only(left: 12),
      color: Colors.transparent,
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          const DynamicAppIcon(size: 14),
          const SizedBox(width: 8),
          Text(
            "SNAPDNS",
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.onSurface.withValues(
                alpha: 0.3,
              ),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(width: 12),
          _StatusDot(active: dns.isServiceConnected, accent: accent),
        ],
      ),
    );

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: isDesktop
                ? DragToMoveArea(
                    child: brandHeader) // Only drag window on Desktop
                : brandHeader,
          ),
          if (isDesktop) ...[
            _TitleBtn(
                icon: Icons.remove, onTap: () => windowManager.minimize()),
            _TitleBtn(
              icon: Icons.close,
              onTap: () => settings.handleWindowClose(),
              isClose: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _TitleBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isClose;
  const _TitleBtn({
    required this.icon,
    required this.onTap,
    this.isClose = false,
  });

  @override
  State<_TitleBtn> createState() => _TitleBtnState();
}

class _TitleBtnState extends State<_TitleBtn> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 46,
          height: 32,
          color: Colors.transparent,
          child: Icon(
            widget.icon,
            size: 14,
            color: _isHovered
                ? (widget.isClose
                    ? Colors.redAccent
                    : theme.colorScheme.onSurface)
                : theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final bool active;
  final Color accent;
  const _StatusDot({required this.active, required this.accent});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? accent : Colors.redAccent,
      ),
    );
  }
}
