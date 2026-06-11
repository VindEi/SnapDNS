import 'package:flutter/material.dart';

class DnsCard extends StatelessWidget {
  final Widget child;
  final double padding;

  const DnsCard({super.key, required this.child, this.padding = 18});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surface, // Pulls the slightly lighter matte gray
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: child,
    );
  }
}
