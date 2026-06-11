import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../../../providers/settings_provider.dart';
import '../../../utils/icon_engine.dart'; // Unified logic

class DynamicAppIcon extends StatefulWidget {
  final double size;
  const DynamicAppIcon({super.key, this.size = 32});

  @override
  State<DynamicAppIcon> createState() => _DynamicAppIconState();
}

class _DynamicAppIconState extends State<DynamicAppIcon> {
  String? _svgTemplate;

  @override
  void initState() {
    super.initState();
    _loadTemplate();
  }

  Future<void> _loadTemplate() async {
    final data = await rootBundle.loadString('assets/SnapDns.svg');
    if (mounted) setState(() => _svgTemplate = data);
  }

  @override
  Widget build(BuildContext context) {
    if (_svgTemplate == null) {
      return SizedBox(width: widget.size, height: widget.size);
    }

    final settings = context.watch<SettingsProvider>();
    final fillHex =
        '#${settings.accentColor.toARGB32().toRadixString(16).substring(2).toLowerCase()}';
    final strokeHex = settings.isDarkMode ? '#bbbbbb' : '#444444';

    // PINPOINTED FIX: Use the exact same logic that worked for the disk files
    final processed = IconEngine.applyColors(_svgTemplate!, fillHex, strokeHex);

    return SvgPicture.string(
      processed,
      width: widget.size,
      height: widget.size,
    );
  }
}
