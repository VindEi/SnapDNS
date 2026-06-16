import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/dns_provider.dart';
import '../../providers/dns_input_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/dns_configuration.dart';
import '../../providers/toast_provider.dart';
import '../widgets/common/dns_card.dart';
import '../widgets/common/action_button.dart';
import '../widgets/main/network_status_bar.dart';
import '../widgets/main/protocol_toggle.dart';
import '../widgets/main/dns_input_stack.dart';
import '../widgets/main/profile_chip.dart';
import '../widgets/profiles/profile_editor.dart';

class MainPage extends StatelessWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        context.select<SettingsProvider, bool>((s) => s.isDesktop);
    final isSystemDnsSaved =
        context.select<DnsProvider, bool>((d) => d.isSystemDnsSaved);
    final smartProviderName =
        context.select<DnsProvider, String>((d) => d.smartProviderName);
    final smartDnsValues =
        context.select<DnsProvider, List<String>>((d) => d.smartDnsValues);
    final isMobileConnected =
        context.select<DnsProvider, bool>((d) => d.isMobileConnected);
    final profiles =
        context.select<DnsProvider, List<DnsConfiguration>>((d) => d.profiles);
    final cs = Theme.of(context).colorScheme;

    final mainContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          isDesktop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        DnsCard(
          child: Column(
            crossAxisAlignment: isDesktop
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              if (isDesktop) const NetworkStatusBar(),
              if (isDesktop) const SizedBox(height: 20),
              Row(
                mainAxisAlignment: isDesktop
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  _label(isDesktop ? "CURRENT RESOLVER" : "VPN TUNNEL", cs),
                  if (isDesktop) const Spacer(),
                  if (isDesktop && !isSystemDnsSaved)
                    _saveActiveBtn(context, cs),
                ],
              ),
              const SizedBox(height: 12),
              _buildReadout(context, smartDnsValues, cs, isDesktop),
              const SizedBox(height: 16),
              Text(
                smartProviderName,
                style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 0.8),
              ),
              if (!isDesktop && !isSystemDnsSaved) ...[
                const SizedBox(height: 16),
                _saveActiveBtn(context, cs),
              ]
            ],
          ),
        ),
        const SizedBox(height: 16),
        DnsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text("Choose & Connect",
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface)),
                  const Spacer(),
                  const ProtocolToggle(),
                ],
              ),
              const SizedBox(height: 20),
              const DnsInputStack(),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: profiles
                    .take(3)
                    .map((p) => _buildChip(context, p))
                    .toList(),
              ),
              const SizedBox(height: 24),
              if (isDesktop)
                Row(
                  children: [
                    Expanded(
                        child: ActionButton(
                      label: "Connect",
                      onTap: () => _handleConnect(context),
                      backgroundColor: cs.primary,
                      textColor: cs
                          .primary.contrastColor, // FIX: Dynamic text contrast!
                    )),
                    const SizedBox(width: 12),
                    Expanded(
                        child: ActionButton(
                            label: "Restore",
                            onTap: context.read<DnsProvider>().resetToDefaults,
                            backgroundColor:
                                cs.onSurface.withValues(alpha: 0.05),
                            textColor: cs.onSurface.withValues(alpha: 0.7),
                            outlined: true)),
                  ],
                )
              else
                ActionButton(
                  label: isMobileConnected ? "Disconnect" : "Connect",
                  onTap: isMobileConnected
                      ? context.read<DnsProvider>().resetToDefaults
                      : () => _handleConnect(context),
                  backgroundColor:
                      isMobileConnected ? Colors.redAccent : cs.primary,
                  textColor: isMobileConnected
                      ? Colors.white
                      : cs.primary.contrastColor, // FIX: Dynamic text contrast!
                ),
            ],
          ),
        ),
      ],
    );

    return isDesktop
        ? ListView(padding: const EdgeInsets.all(16.0), children: [mainContent])
        : Center(
            child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: mainContent));
  }

  Widget _buildChip(BuildContext context, DnsConfiguration p) {
    final isSelected =
        context.select<DnsInputProvider, bool>((i) => i.isInputMatch(p));
    return ProfileChip(
      label: p.name,
      isSelected: isSelected,
      onTap: () => context.read<DnsInputProvider>().loadProfile(p),
    );
  }

  Widget _saveActiveBtn(BuildContext context, ColorScheme cs) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: () => showDialog(
              context: context,
              builder: (_) => ProfileEditor(
                  profile: context.read<DnsProvider>().getSystemAsConfig())),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
                borderRadius: BorderRadius.circular(4)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add_rounded, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Text("SAVE",
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: cs.primary))
            ]),
          ),
        ),
      );

  Widget _buildReadout(BuildContext context, List<String> values,
          ColorScheme cs, bool isDesktop) =>
      GestureDetector(
        onTap: () =>
            context.read<DnsProvider>().copyToClipboard(values.join(", ")),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Column(
            crossAxisAlignment: isDesktop
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: values
                .map((ip) => Text(ip,
                    textAlign: isDesktop ? TextAlign.left : TextAlign.center,
                    style: TextStyle(
                        fontSize: values.length > 1 ? 20 : 26,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Consolas',
                        color: cs.onSurface)))
                .toList(),
          ),
        ),
      );

  Widget _label(String t, ColorScheme cs) => Text(t,
      style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: cs.onSurface.withValues(alpha: 0.3),
          letterSpacing: 1.2));

  void _handleConnect(BuildContext context) {
    final input = context.read<DnsInputProvider>();
    if (!input.isInputValid) {
      context.read<ToastProvider>().showToast("INVALID FORMAT");
      return;
    }
    DnsConfiguration config;
    if (input.activeMode == DnsInputMode.link) {
      config = DnsConfiguration(
        dohUrl: input.activeSecureType == SecureType.doh
            ? input.dohController.text.trim()
            : "",
        dotHostname: input.activeSecureType == SecureType.dot
            ? input.dotController.text.trim()
            : "",
      );
    } else {
      config = DnsConfiguration(
        primaryDns: input.p4Controller.text.trim(),
        secondaryDns: input.s4Controller.text.trim(),
      );
    }
    context
        .read<DnsProvider>()
        .connectDns(config, context.read<SettingsProvider>());
  }
}
