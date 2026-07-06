import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../providers/settings_provider.dart';
import '../../../services/update_service.dart';

// Official GitHub Vector Logo (Normalized 24x24)
const String _githubSvg = '''
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <path fill="currentColor" d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/>
</svg>
''';

class UpdateDialog extends StatelessWidget {
  final UpdateInfo info;
  const UpdateDialog({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    return _UpdateDialogContent(info: info);
  }
}

class _UpdateDialogContent extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateDialogContent({required this.info});

  @override
  State<_UpdateDialogContent> createState() => _UpdateDialogContentState();
}

class _UpdateDialogContentState extends State<_UpdateDialogContent> {
  bool _isDownloading = false;
  double _progress = 0.0;

  List<Widget> _parseMarkdown(String markdown, ColorScheme cs) {
    final lines = markdown.split('\n');
    final List<Widget> widgets = [];

    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 4));
        continue;
      }

      if (trimmed.startsWith('###')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            trimmed.replaceFirst('###', '').trim().toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: cs.primary,
              letterSpacing: 1.0,
            ),
          ),
        ));
      } else if (trimmed.startsWith('##')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Text(
            trimmed.replaceFirst('##', '').trim().toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
              letterSpacing: 1.2,
            ),
          ),
        ));
      } else if (trimmed.startsWith('*') || trimmed.startsWith('-')) {
        final cleanText = trimmed.substring(1).trim();
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("• ",
                  style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cleanDisplayLine(cleanText),
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.8),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ));
      } else {
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            cleanDisplayLine(trimmed),
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.7),
              height: 1.4,
            ),
          ),
        ));
      }
    }
    return widgets;
  }

  String cleanDisplayLine(String raw) {
    return raw.replaceAll('**', '');
  }

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _parseMarkdown(widget.info.changelog, cs),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_isDownloading) ...[
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
            ] else ...[
              Row(
                children: [
                  // FIX: Restored the custom dark-themed tooltip wrapper
                  Tooltip(
                    message: "OPEN GITHUB RELEASE",
                    decoration: BoxDecoration(
                      color: const Color(0xFF151515),
                      borderRadius: BorderRadius.circular(4),
                      border:
                          Border.all(color: cs.outline.withValues(alpha: 0.1)),
                    ),
                    textStyle: TextStyle(
                      color: cs.onSurface,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                    child: IconButton(
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        backgroundColor: cs.onSurface.withValues(alpha: 0.02),
                        side: BorderSide(
                            color: cs.outline.withValues(alpha: 0.1)),
                      ),
                      onPressed: () => launchUrl(
                        Uri.parse(widget.info.releasePageUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                      // FIX: Restored the standard vector GitHub logo (no text)
                      icon: SvgPicture.string(
                        _githubSvg,
                        width: 14,
                        height: 14,
                        colorFilter:
                            ColorFilter.mode(cs.primary, BlendMode.srcIn),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // FIX: Added 'styleFrom' shape constraints to prevent the LATER button from being pill-shaped/too round
                  TextButton(
                    style: TextButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
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
                      final navigator = Navigator.of(context);

                      setState(() => _isDownloading = true);
                      await UpdateService.performUpdate(context, widget.info,
                          (p) {
                        if (mounted) {
                          setState(() => _progress = p);
                        }
                      });

                      if (!mounted) return;

                      if (Platform.isAndroid) {
                        navigator.pop();
                      }
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
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
              )
            ],
          ],
        ),
      ),
    );
  }
}
