import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/dns_provider.dart';
import '../../../providers/dns_input_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../models/dns_configuration.dart';
import '../../../utils/dns_intelligence.dart';

class ProfileCard extends StatelessWidget {
  final DnsConfiguration config;
  final bool isExpanded, isActive;
  final VoidCallback onToggle, onEdit, onDelete;
  final int index;

  const ProfileCard({
    super.key,
    required this.config,
    required this.isExpanded,
    required this.isActive,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.index,
  });

  // ULTRA-SMART SUBTITLE GENERATOR (Shows Main Address + Protocol Tags)
  String _getSubtitle(DnsConfiguration c) {
    String mainInfo = "";
    List<String> tags = [];

    // 1. Determine the Primary Display Info
    if (c.primaryDns.isNotEmpty) {
      mainInfo = c.primaryDns;
      if (c.ipv6Primary.isNotEmpty) tags.add("IPv6");
      if (c.dohUrl.isNotEmpty) tags.add("DoH");
      if (c.dotHostname.isNotEmpty) tags.add("DoT");
    } else if (c.ipv6Primary.isNotEmpty) {
      mainInfo = c.ipv6Primary;
      if (c.dohUrl.isNotEmpty) tags.add("DoH");
      if (c.dotHostname.isNotEmpty) tags.add("DoT");
    } else if (c.dohUrl.isNotEmpty) {
      mainInfo = c.dohUrl.replaceFirst(RegExp(r'^https?://'), '');
      if (c.dotHostname.isNotEmpty) tags.add("DoT");
    } else if (c.dotHostname.isNotEmpty) {
      mainInfo = c.dotHostname;
    } else {
      return "UNCONFIGURED";
    }

    // 2. Format with Pipe separators
    if (tags.isEmpty) return mainInfo;
    return "$mainInfo | ${tags.join(' | ')}";
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMatched =
        context.select<DnsInputProvider, bool>((i) => i.isInputMatch(config));

    final currentLatencyMs = context.select<DnsProvider, int>((d) => d.profiles
        .firstWhere((p) => p.id == config.id, orElse: () => config)
        .latencyMs);

    Color statusColor =
        isActive ? Colors.greenAccent : (isMatched ? cs.primary : cs.outline);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: (isMatched || isActive)
                ? statusColor.withValues(alpha: 0.4)
                : cs.outline.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                        width: 3,
                        height: 18,
                        decoration: BoxDecoration(
                            color: (isMatched || isActive)
                                ? statusColor
                                : cs.onSurface.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(1))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(config.name.toUpperCase(),
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 10,
                                  color: (isMatched || isActive)
                                      ? statusColor
                                      : cs.onSurface.withValues(alpha: 0.8))),

                          // THE NEW SUBTITLE
                          Text(_getSubtitle(config),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 10,
                                  fontFamily: 'Consolas')),
                        ],
                      ),
                    ),
                    _LatencyIndicator(ms: currentLatencyMs),
                    const SizedBox(width: 12),
                    ReorderableDragStartListener(
                        index: index,
                        child: MouseRegion(
                            cursor: SystemMouseCursors.grab,
                            child: Icon(Icons.drag_indicator_rounded,
                                size: 18,
                                color: cs.onSurface.withValues(alpha: 0.1)))),
                  ],
                ),
              ),
            ),
          ),
          if (isExpanded) _buildActions(context, cs),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, ColorScheme cs) => Container(
        height: 36,
        decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: 0.02),
            border: Border(
                top: BorderSide(color: cs.outline.withValues(alpha: 0.1)))),
        child: Row(
          children: [
            _btn("LOAD", cs.primary, () {
              context.read<DnsInputProvider>().loadProfile(config);
              context.read<SettingsProvider>().setPage(1);
            }),
            _btn(
                "SHARE",
                cs.onSurface.withValues(alpha: 0.4),
                () => context
                    .read<DnsProvider>()
                    .copyToClipboard(DnsIntelligence.formatForSharing(config))),
            _btn("EDIT", cs.onSurface.withValues(alpha: 0.4), onEdit),
            _DeleteButton(onDelete: onDelete),
          ],
        ),
      );

  Widget _btn(String l, Color c, VoidCallback t) => Expanded(
      child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: InkWell(
              onTap: t,
              child: Center(
                  child: Text(l,
                      style: TextStyle(
                          color: c,
                          fontWeight: FontWeight.w900,
                          fontSize: 9,
                          letterSpacing: 1.2))))));
}

class _LatencyIndicator extends StatelessWidget {
  final int ms;
  const _LatencyIndicator({required this.ms});
  @override
  Widget build(BuildContext context) {
    Color color = Colors.greenAccent;
    if (ms > 150) color = Colors.orangeAccent;
    if (ms > 300 || ms < 0) color = Colors.redAccent;
    return Text(ms < 0 ? "--" : "${ms}MS",
        style: TextStyle(
            color: color.withValues(alpha: 0.7),
            fontSize: 9,
            fontWeight: FontWeight.bold,
            fontFamily: 'Consolas'));
  }
}

class _DeleteButton extends StatefulWidget {
  final VoidCallback onDelete;
  const _DeleteButton({required this.onDelete});
  @override
  State<_DeleteButton> createState() => _DeleteButtonState();
}

class _DeleteButtonState extends State<_DeleteButton> {
  bool _confirm = false;
  Timer? _timer;

  void _handle() {
    if (_confirm) {
      widget.onDelete();
    } else {
      setState(() => _confirm = true);
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _confirm = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Expanded(
      child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: InkWell(
              onTap: _handle,
              child: Center(
                  child: Text(_confirm ? "CONFIRM?" : "DELETE",
                      style: TextStyle(
                          color: _confirm ? Colors.redAccent : Colors.grey,
                          fontWeight: FontWeight.w900,
                          fontSize: 9))))));
}
