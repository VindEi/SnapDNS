import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/dns_configuration.dart';
import '../../providers/dns_provider.dart';
import '../widgets/profiles/profile_card.dart';
import '../widgets/profiles/profile_editor.dart';
import '../widgets/profiles/profile_group_card.dart';
import 'public_dns_page.dart';

sealed class _ProfileEntry {
  final String keyId;
  _ProfileEntry(this.keyId);
}

class _SingleEntry extends _ProfileEntry {
  final DnsConfiguration config;
  _SingleEntry(this.config) : super(config.id);
}

class _GroupEntry extends _ProfileEntry {
  final String groupName;
  final List<DnsConfiguration> profiles;
  _GroupEntry(this.groupName, this.profiles) : super("group_$groupName");
}

class ProfilesPage extends StatefulWidget {
  const ProfilesPage({super.key});

  @override
  State<ProfilesPage> createState() => _ProfilesPageState();
}

class _ProfilesPageState extends State<ProfilesPage> {
  int? _expandedIndex;

  List<_ProfileEntry> _buildEntries(List<DnsConfiguration> profiles) {
    final List<_ProfileEntry> entries = [];
    final Map<String, List<DnsConfiguration>> groups = {};
    final List<String> ordering = [];

    for (var p in profiles) {
      final g = p.group.trim();
      if (g.isNotEmpty) {
        if (!groups.containsKey(g)) {
          groups[g] = [];
          ordering.add("group:$g");
        }
        groups[g]!.add(p);
      } else {
        ordering.add("single:${p.id}");
      }
    }

    for (var token in ordering) {
      if (token.startsWith("group:")) {
        final g = token.substring(6);
        final list = groups[g]!;
        if (list.length > 1) {
          entries.add(_GroupEntry(g, list));
        } else {
          entries.add(_SingleEntry(list.first));
        }
      } else {
        final id = token.substring(7);
        final profile = profiles.cast<DnsConfiguration?>().firstWhere(
              (p) => p != null && p.id == id,
              orElse: () => null,
            );
        if (profile != null) {
          entries.add(_SingleEntry(profile));
        }
      }
    }

    return entries;
  }

  void _handleReorder(int oldIndex, int newIndex, List<_ProfileEntry> entries,
      DnsProvider dns) {
    final item = entries.removeAt(oldIndex);
    entries.insert(newIndex, item);

    final List<DnsConfiguration> flattened = [];
    for (var entry in entries) {
      if (entry is _GroupEntry) {
        flattened.addAll(entry.profiles);
      } else if (entry is _SingleEntry) {
        flattened.add(entry.config);
      }
    }

    dns.setProfiles(flattened);
  }

  @override
  Widget build(BuildContext context) {
    final dns = context.watch<DnsProvider>();
    final entries = _buildEntries(dns.profiles);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Stack(
            children: [
              ReorderableListView.builder(
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                header: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Text(
                        "PROFILES",
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.3),
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const PublicDnsPage()),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.25),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.public_rounded,
                                    size: 13,
                                    color:
                                        Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  "PUBLIC DIRECTORY",
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                itemCount: entries.length,
                onReorderItem: (int oldIndex, int newIndex) {
                  _handleReorder(oldIndex, newIndex, entries, dns);
                },
                itemBuilder: (context, index) {
                  final entry = entries[index];

                  if (entry is _GroupEntry) {
                    return ProfileGroupCard(
                      key: ValueKey(entry.keyId),
                      groupName: entry.groupName,
                      profiles: entry.profiles,
                      index: index,
                      systemPrimary: dns.systemPrimary,
                      onEdit: (p) => _showEditor(context, p),
                      onDelete: (p) => dns.deleteProfile(p),
                    );
                  }

                  final p = (entry as _SingleEntry).config;
                  return ProfileCard(
                    key: ValueKey(p.id),
                    config: p,
                    index: index,
                    isExpanded: _expandedIndex == index,
                    isActive: dns.systemPrimary == p.primaryDns ||
                        dns.systemPrimary == p.ipv6Primary ||
                        dns.systemPrimary == p.dohUrl ||
                        dns.systemPrimary == p.dotHostname,
                    onToggle: () => setState(
                      () => _expandedIndex =
                          _expandedIndex == index ? null : index,
                    ),
                    onEdit: () => _showEditor(context, p),
                    onDelete: () {
                      setState(() => _expandedIndex = null);
                      dns.deleteProfile(p);
                    },
                  );
                },
              ),
              Positioned(
                bottom: 20,
                left: 20,
                child: _TechFab(
                  icon: Icons.refresh_rounded,
                  onTap: dns.refreshLatencies,
                ),
              ),
              Positioned(
                bottom: 20,
                right: 20,
                child: _TechFab(
                  icon: Icons.add,
                  onTap: () => _showEditor(context, null),
                  isAccent: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditor(BuildContext context, dynamic p) => showDialog(
        context: context,
        builder: (_) => ProfileEditor(profile: p),
      );
}

class _TechFab extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isAccent;

  const _TechFab({
    required this.icon,
    required this.onTap,
    this.isAccent = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: isAccent ? cs.primary : cs.surface,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              border: Border.all(color: cs.outline.withValues(alpha: 0.1)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              icon,
              color: isAccent ? Colors.black : cs.primary,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
