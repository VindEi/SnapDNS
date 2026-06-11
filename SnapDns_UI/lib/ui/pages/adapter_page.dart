import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/dns_provider.dart';
import '../widgets/adapters/adapter_tile.dart';

class AdapterPage extends StatelessWidget {
  const AdapterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final dns = context.watch<DnsProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            _PrecisionBackButton(onTap: () => Navigator.pop(context)),
            const Expanded(
              child: Center(
                child: Text(
                  "NETWORK ADAPTERS",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 32),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            color: colorScheme.outline.withValues(alpha: 0.05),
            height: 1,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabel("SYSTEM DEFAULT", colorScheme),
            const SizedBox(height: 10),
            AdapterTile(
              title: "Automatic Detection",
              subtitle: "Detect and use the primary active interface.",
              isSelected: dns.isAdapterSelected(null),
              onTap: () => dns.setSelectedAdapter(null),
            ),
            const SizedBox(height: 32),
            _buildLabel("HARDWARE INTERFACES", colorScheme),
            const SizedBox(height: 10),
            Expanded(
              child: dns.adapters.isEmpty
                  ? _buildEmptyState(colorScheme)
                  : ListView.builder(
                      itemCount: dns.adapters.length,
                      itemBuilder: (context, index) {
                        final adapter = dns.adapters[index];
                        return AdapterTile(
                          title: adapter,
                          subtitle: _getAdapterType(adapter),
                          isSelected: dns.isAdapterSelected(adapter),
                          onTap: () => dns.setSelectedAdapter(adapter),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text, ColorScheme cs) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w900,
        color: cs.onSurface.withValues(alpha: 0.2),
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lan_outlined,
            size: 32,
            color: cs.onSurface.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 12),
          Text(
            "SCANNING...",
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurface.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }

  String _getAdapterType(String name) {
    final n = name.toLowerCase();
    if (n.contains("wi-fi") || n.contains("wlan")) return "Wireless Connection";
    if (n.contains("ethernet") || n.contains("lan")) return "Wired Connection";
    return "Network Interface";
  }
}

class _PrecisionBackButton extends StatefulWidget {
  final VoidCallback onTap;
  const _PrecisionBackButton({required this.onTap});

  @override
  State<_PrecisionBackButton> createState() => _PrecisionBackButtonState();
}

class _PrecisionBackButtonState extends State<_PrecisionBackButton> {
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
