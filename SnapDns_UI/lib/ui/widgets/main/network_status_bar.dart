import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/dns_provider.dart';
import '../../pages/adapter_page.dart';

class NetworkStatusBar extends StatelessWidget {
  const NetworkStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.primary;

    return InkWell(
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const AdapterPage())),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                Icons.router_rounded,
                size: 14,
                color: accent.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("INTERFACE",
                    style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: Colors.grey)),
                Selector<DnsProvider, String>(
                  selector: (_, p) => p.readableAdapterName,
                  builder: (_, name, __) => Text(
                    // FIXED: Renamed duplicate _ to __
                    name.toUpperCase(),
                    style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.grey, size: 12),
          ],
        ),
      ),
    );
  }
}
