import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/dns_input_provider.dart';

class ProtocolToggle extends StatelessWidget {
  const ProtocolToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.primary;
    final input = context.watch<DnsInputProvider>();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(1),
          decoration: BoxDecoration(
              color: colorScheme.onSurface.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(4)),
          child: Row(
            children: input.activeMode == DnsInputMode.ip
                ? [
                    _MiniBtn(
                        label: "v4",
                        active: input.activeIpType == IpType.v4,
                        onTap: () => input.setIpType(IpType.v4),
                        accent: accent),
                    _MiniBtn(
                        label: "v6",
                        active: input.activeIpType == IpType.v6,
                        onTap: () => input.setIpType(IpType.v6),
                        accent: accent),
                  ]
                : [
                    _MiniBtn(
                        label: "DoT",
                        active: input.activeSecureType == SecureType.dot,
                        onTap: () => input.setSecureType(SecureType.dot),
                        accent: accent),
                    _MiniBtn(
                        label: "DoH",
                        active: input.activeSecureType == SecureType.doh,
                        onTap: () => input.setSecureType(SecureType.doh),
                        accent: accent),
                  ],
          ),
        ),
        const SizedBox(width: 8),
        _ModeSwitcherIcon(input: input),
      ],
    );
  }
}

class _ModeSwitcherIcon extends StatefulWidget {
  final DnsInputProvider input;
  const _ModeSwitcherIcon({required this.input});

  @override
  State<_ModeSwitcherIcon> createState() => _ModeSwitcherIconState();
}

class _ModeSwitcherIconState extends State<_ModeSwitcherIcon> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.input.toggleInputMode,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: _isHovered
                  ? colorScheme.onSurface.withValues(alpha: 0.05)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4)),
          child: Icon(
              widget.input.activeMode == DnsInputMode.ip
                  ? Icons.link_rounded
                  : Icons.numbers_rounded,
              size: 18,
              color: _isHovered
                  ? colorScheme.onSurface
                  : colorScheme.onSurface.withValues(alpha: 0.2)),
        ),
      ),
    );
  }
}

class _MiniBtn extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color accent;

  const _MiniBtn(
      {required this.label,
      required this.active,
      required this.onTap,
      required this.accent});

  @override
  State<_MiniBtn> createState() => _MiniBtnState();
}

class _MiniBtnState extends State<_MiniBtn> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color: widget.active
                  ? widget.accent
                  : (_isHovered
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(3)),
          child: Text(widget.label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: widget.active
                      ? Colors.black
                      : (_isHovered ? Colors.white : Colors.white24))),
        ),
      ),
    );
  }
}
