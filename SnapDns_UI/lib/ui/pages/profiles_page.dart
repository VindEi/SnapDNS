import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/dns_provider.dart';
import '../widgets/profiles/profile_card.dart';
import '../widgets/profiles/profile_editor.dart';

class ProfilesPage extends StatefulWidget {
  const ProfilesPage({super.key});
  @override
  State<ProfilesPage> createState() => _ProfilesPageState();
}

class _ProfilesPageState extends State<ProfilesPage> {
  int? _expandedIndex;

  @override
  Widget build(BuildContext context) {
    final dns = context.watch<DnsProvider>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: dns.profiles.length,
            // Updated to the newer onReorder property required by latest Flutter
            onReorderItem: (int oldIndex, int newIndex) {
              dns.reorderProfiles(oldIndex, newIndex);
            },
            itemBuilder: (context, index) {
              final p = dns.profiles[index];
              return ProfileCard(
                key: ValueKey(p.id),
                config: p,
                index: index,
                isExpanded: _expandedIndex == index,
                isActive: dns.systemPrimary == p.primaryDns ||
                    dns.systemPrimary == p.dohUrl,
                onToggle: () => setState(
                  () => _expandedIndex = _expandedIndex == index ? null : index,
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
