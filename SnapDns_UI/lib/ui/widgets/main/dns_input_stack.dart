import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/dns_input_provider.dart';

class DnsInputStack extends StatelessWidget {
  const DnsInputStack({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.primary;
    final input = context
        .watch<DnsInputProvider>(); // Watching the isolated UI State only!

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: input.activeMode == DnsInputMode.ip
          ? Row(
              key: ValueKey("ip_${input.activeIpType}"),
              children: [
                Expanded(
                    child: _buildField(
                        input.activeIpType == IpType.v4
                            ? "Primary IPv4"
                            : "Primary IPv6",
                        input.primaryController,
                        accent,
                        colorScheme)),
                const SizedBox(width: 8),
                Expanded(
                    child: _buildField("Backup (Opt)",
                        input.secondaryController, accent, colorScheme)),
              ],
            )
          : _buildField(
              input.activeSecureType == SecureType.doh
                  ? "DoH URL (https://...)"
                  : "DoT Hostname (dns.example.com)",
              input.activeSecureController,
              accent,
              colorScheme,
              key: ValueKey("link_${input.activeSecureType}"),
            ),
    );
  }

  Widget _buildField(String hint, TextEditingController controller,
      Color accent, ColorScheme colorScheme,
      {Key? key}) {
    return SizedBox(
      key: key,
      height: 45,
      child: TextField(
        controller: controller,
        style: TextStyle(
            color: colorScheme.onSurface, fontSize: 13, fontFamily: 'Consolas'),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.2),
              fontSize: 12),
          filled: true,
          fillColor: colorScheme.onSurface.withValues(alpha: 0.03),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.1))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: accent, width: 1.5)),
        ),
      ),
    );
  }
}
