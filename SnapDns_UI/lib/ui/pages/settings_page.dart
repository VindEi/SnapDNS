import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/dns_intelligence.dart';
import '../../models/dns_configuration.dart';
import '../../services/mobile_vpn_engine.dart';
import '../../providers/settings_provider.dart';
import '../../providers/dns_provider.dart';
import '../widgets/settings/settings_tile.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    final dns = context.read<DnsProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        children: [
          const _Label(text: "GENERAL"),
          _Card([
            SettingsSwitch(
              title: s.isDesktop ? "Run on Startup" : "Auto-Connect on Boot",
              subtitle: s.isDesktop
                  ? "Start SnapDns with the system."
                  : "Connect DNS automatically when phone starts.",
              value: s.runOnStartup,
              onChanged: s.toggleRunOnStartup,
            ),
            if (s.isDesktop) ...[
              SettingsSwitch(
                title: "Minimize to Tray",
                subtitle: "Keep app running when closed.",
                value: s.minimizeToTray,
                onChanged: s.toggleTray,
              ),
              SettingsSwitch(
                title: "Launch Hidden",
                subtitle: "Start silently on boot.",
                value: s.launchHidden,
                onChanged: s.toggleLaunchHidden,
              ),
            ],
            if (!s.isDesktop)
              _listTile(
                "Always-On VPN Settings",
                Icons.vpn_lock_rounded,
                () => MobileVpnEngine.openVpnSettings(),
                colorScheme,
              ),
            SettingsSwitch(
              title: "Show Notifications",
              subtitle: "Alert on status changes.",
              value: s.showNotifications,
              onChanged: s.toggleNotifications,
            ),
          ]),
          const SizedBox(height: 24),
          const _Label(text: "APPEARANCE"),
          _Card([
            SettingsSwitch(
              title: "Dark Theme",
              subtitle: "Switch to deep black mode.",
              value: s.isDarkMode,
              onChanged: (_) => s.toggleTheme(),
            ),
            _buildAccentPicker(s, colorScheme),
          ]),
          const SizedBox(height: 24),
          const _Label(text: "DATA MANAGEMENT"),
          _actionBtn(
            s.resetButtonText,
            Icons.history_rounded,
            () => s.resetProviders(dns.resetToDefaultProfiles),
            s.isResetConfirming ? Colors.redAccent : accent,
            colorScheme,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  "EXPORT",
                  Icons.upload_rounded,
                  () => s.exportProfiles(jsonEncode(dns.profiles)),
                  accent,
                  colorScheme,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _actionBtn(
                  "IMPORT",
                  Icons.download_rounded,
                  () => s.importProfiles((data) {
                    if (mounted) {
                      dns.smartImport(
                        DnsIntelligence.parseHumanText(data) ??
                            DnsConfiguration(name: "Imported"),
                      );
                    }
                  }),
                  accent,
                  colorScheme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _Label(text: "TROUBLESHOOTING"),
          _Card([
            _listTile("Manual Cache Flush", Icons.cleaning_services_rounded,
                dns.flushDns, colorScheme),
            if (s.isDesktop)
              _listTile("Restart System Service", Icons.refresh_rounded,
                  dns.restartService, colorScheme),
            _listTile("External DNS Leak Test", Icons.security_rounded,
                s.openLeakTest, colorScheme),
          ]),
          const SizedBox(height: 40),
          Center(
            child: Text(
              s.versionText,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.2),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccentPicker(SettingsProvider s, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("ACCENT COLOR",
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Colors.grey)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _colorCircle(s, const Color(0xFF00C8C8)),
              _colorCircle(s, const Color(0xFF007AFF)),
              _colorCircle(s, const Color(0xFFAF52DE)),
              _colorCircle(s, const Color(0xFFFF9500)),
              _colorCircle(s, const Color(0xFFFF2D55)),
              _colorCircle(s, const Color(0xFF4CD964)),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 35,
            child: TextField(
              onChanged: s.updateAccentHex,
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
              decoration: InputDecoration(
                hintText: "CUSTOM HEX",
                hintStyle:
                    TextStyle(color: cs.onSurface.withValues(alpha: 0.1)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                filled: true,
                fillColor: cs.onSurface.withValues(alpha: 0.02),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorCircle(SettingsProvider s, Color color) {
    bool isSelected = s.accentColor.toARGB32() == color.toARGB32();
    return InkWell(
      onTap: () => s.updateAccentColor(color),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border:
                isSelected ? Border.all(color: Colors.white, width: 2) : null),
        child: isSelected
            ? const Icon(Icons.check, size: 12, color: Colors.white)
            : null,
      ),
    );
  }

  // FIXED ALIGNMENT HERE
  Widget _actionBtn(String label, IconData icon, VoidCallback onTap,
          Color color, ColorScheme cs) =>
      Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.center, // THIS MAKES IT PERFECTLY CENTERED
            decoration: BoxDecoration(
              border: Border.all(color: cs.outline.withValues(alpha: 0.1)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 10),
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 10)),
              ],
            ),
          ),
        ),
      );

  Widget _listTile(String t, IconData i, VoidCallback onTap, ColorScheme cs) =>
      ListTile(
        onTap: onTap,
        leading: Icon(i, size: 18, color: cs.onSurface.withValues(alpha: 0.4)),
        title: Text(t,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.chevron_right, size: 16),
        dense: true,
      );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label({required this.text});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Colors.grey,
                letterSpacing: 1.5)),
      );
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card(this.children);
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(4),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
            border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(4)),
        child: Column(children: children),
      ),
    );
  }
}
