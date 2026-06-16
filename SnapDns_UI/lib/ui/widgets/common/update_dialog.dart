import 'dart:io';
import 'package:flutter/material.dart';
import '../../../providers/settings_provider.dart';
import '../../../services/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const UpdateDialog({super.key, required this.info});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.1)),
      ),
      title: Row(
        children: [
          Icon(Icons.system_update_rounded, color: cs.primary, size: 20),
          const SizedBox(width: 10),
          Text(
            "UPDATE AVAILABLE (v${widget.info.version})",
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 350,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "CHANGELOG",
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w900,
                color: Colors.grey,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(4),
                    border:
                        Border.all(color: cs.outline.withValues(alpha: 0.05)),
                  ),
                  child: Text(
                    widget.info.changelog,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withValues(alpha: 0.8),
                      height: 1.5,
                      fontFamily: 'Consolas',
                    ),
                  ),
                ),
              ),
            ),
            if (_isDownloading) ...[
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: cs.onSurface.withValues(alpha: 0.1),
                color: cs.primary,
                minHeight: 4,
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  "DOWNLOADING... ${(_progress * 100).toInt()}%",
                  style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey),
                ),
              ),
            ]
          ],
        ),
      ),
      actions: _isDownloading
          ? []
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  "LATER",
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.3),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () async {
                  // FIX: Capture the navigator state before the async gap to satisfy the linter
                  final navigator = Navigator.of(context);

                  setState(() => _isDownloading = true);
                  await UpdateService.performUpdate(context, widget.info, (p) {
                    if (mounted) {
                      setState(() => _progress = p);
                    }
                  });

                  if (!mounted) return;

                  if (Platform.isAndroid) {
                    navigator.pop(); // Safe to pop now!
                  }
                },
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    "UPDATE NOW",
                    style: TextStyle(
                      color: cs.primary.contrastColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
    );
  }
}
