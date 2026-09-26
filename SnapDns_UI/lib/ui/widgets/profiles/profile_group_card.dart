import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/dns_configuration.dart';
import '../../../providers/dns_input_provider.dart';
import '../../../providers/dns_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../utils/dns_intelligence.dart';

class ProfileGroupCard extends StatefulWidget {
  final String groupName;
  final List<DnsConfiguration> profiles;
  final int index;
  final String systemPrimary;
  final Function(DnsConfiguration) onEdit;
  final Function(DnsConfiguration) onDelete;

  const ProfileGroupCard({
    super.key,
    required this.groupName,
    required this.profiles,
    required this.index,
    required this.systemPrimary,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<ProfileGroupCard> createState() => _ProfileGroupCardState();
}

class _ProfileGroupCardState extends State<ProfileGroupCard> {
  bool _isExpanded = false;
  String? _expandedChildId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final DnsConfiguration? activeChild =
        widget.profiles.cast<DnsConfiguration?>().firstWhere(
              (p) =>
                  p != null &&
                  (p.primaryDns == widget.systemPrimary ||
                      p.ipv6Primary == widget.systemPrimary ||
                      p.dohUrl == widget.systemPrimary ||
                      p.dotHostname == widget.systemPrimary),
              orElse: () => null,
            );

    final bool hasActiveChild = activeChild != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: hasActiveChild
              ? Colors.greenAccent.withValues(alpha: 0.4)
              : cs.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: InkWell(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 18,
                      decoration: BoxDecoration(
                        color: hasActiveChild
                            ? Colors.greenAccent
                            : cs.onSurface.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.groupName.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 10,
                                color: hasActiveChild
                                    ? Colors.greenAccent
                                    : cs.onSurface.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: cs.onSurface.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              "${widget.profiles.length} PROFILES",
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: cs.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                          if (hasActiveChild) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color:
                                    Colors.greenAccent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(2),
                                border: Border.all(
                                    color: Colors.greenAccent
                                        .withValues(alpha: 0.3),
                                    width: 0.8),
                              ),
                              child: Text(
                                _formatActiveBadge(activeChild.name),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.greenAccent,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: 8),
                    ReorderableDragStartListener(
                      index: widget.index,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          size: 18,
                          color: cs.onSurface.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isExpanded)
            Container(
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(color: cs.outline.withValues(alpha: 0.08))),
              ),
              child: Column(
                children: widget.profiles.map((childProfile) {
                  final bool isChildActive =
                      widget.systemPrimary == childProfile.primaryDns ||
                          widget.systemPrimary == childProfile.ipv6Primary ||
                          widget.systemPrimary == childProfile.dohUrl ||
                          widget.systemPrimary == childProfile.dotHostname;

                  final bool isChildExpanded =
                      _expandedChildId == childProfile.id;

                  return Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                            color: cs.outline.withValues(alpha: 0.04)),
                      ),
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: () => setState(() {
                            _expandedChildId =
                                isChildExpanded ? null : childProfile.id;
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isChildActive
                                        ? Colors.greenAccent
                                        : cs.onSurface.withValues(alpha: 0.2),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        childProfile.name,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isChildActive
                                              ? Colors.greenAccent
                                              : cs.onSurface
                                                  .withValues(alpha: 0.85),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _formatChildEndpoints(childProfile),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: cs.onSurface
                                              .withValues(alpha: 0.35),
                                          fontSize: 9,
                                          fontFamily: 'Consolas',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _buildLatency(childProfile.latencyMs),
                                const SizedBox(width: 8),
                                Icon(
                                  isChildExpanded
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  size: 14,
                                  color: cs.onSurface.withValues(alpha: 0.3),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (isChildExpanded)
                          Container(
                            height: 32,
                            decoration: BoxDecoration(
                              color: cs.onSurface.withValues(alpha: 0.02),
                              border: Border(
                                  top: BorderSide(
                                      color:
                                          cs.outline.withValues(alpha: 0.05))),
                            ),
                            child: Row(
                              children: [
                                _actionBtn("LOAD", cs.primary, () {
                                  context
                                      .read<DnsInputProvider>()
                                      .loadProfile(childProfile);
                                  context.read<SettingsProvider>().setPage(1);
                                }),
                                _actionBtn("SHARE",
                                    cs.onSurface.withValues(alpha: 0.4), () {
                                  context.read<DnsProvider>().copyToClipboard(
                                      DnsIntelligence.formatForSharing(
                                          childProfile));
                                }),
                                _actionBtn(
                                    "EDIT",
                                    cs.onSurface.withValues(alpha: 0.4),
                                    () => widget.onEdit(childProfile)),
                                _ChildDeleteButton(
                                    onDelete: () =>
                                        widget.onDelete(childProfile)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  String _formatActiveBadge(String rawName) {
    final stripped = rawName.split('(').first.trim().toUpperCase();
    return stripped.isNotEmpty ? "ACTIVE: $stripped" : "ACTIVE";
  }

  String _formatChildEndpoints(DnsConfiguration c) {
    String mainInfo = "";
    final List<String> tags = [];

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
      try {
        final uri = Uri.parse(c.dohUrl);
        mainInfo = uri.host.isNotEmpty ? uri.host : c.dohUrl;
      } catch (_) {
        mainInfo = c.dohUrl.replaceFirst(RegExp(r'^https?://'), '');
      }
      if (c.dotHostname.isNotEmpty) tags.add("DoT");
    } else if (c.dotHostname.isNotEmpty) {
      mainInfo = c.dotHostname;
    } else {
      return "Unconfigured";
    }

    if (tags.isEmpty) return mainInfo;
    return "$mainInfo | ${tags.join(' | ')}";
  }

  Widget _buildLatency(int ms) {
    Color color = Colors.greenAccent;
    if (ms > 150) color = Colors.orangeAccent;
    if (ms > 300 || ms < 0) color = Colors.redAccent;
    return Text(
      ms < 0 ? "--" : "${ms}MS",
      style: TextStyle(
        color: color.withValues(alpha: 0.7),
        fontSize: 8.5,
        fontWeight: FontWeight.bold,
        fontFamily: 'Consolas',
      ),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 8.5,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChildDeleteButton extends StatefulWidget {
  final VoidCallback onDelete;
  const _ChildDeleteButton({required this.onDelete});

  @override
  State<_ChildDeleteButton> createState() => _ChildDeleteButtonState();
}

class _ChildDeleteButtonState extends State<_ChildDeleteButton> {
  bool _confirm = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _handle() {
    if (_confirm) {
      _timer?.cancel();
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
              child: Text(
                _confirm ? "CONFIRM?" : "DELETE",
                style: TextStyle(
                  color: _confirm ? Colors.redAccent : Colors.grey,
                  fontWeight: FontWeight.w900,
                  fontSize: 8.5,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
        ),
      );
}
