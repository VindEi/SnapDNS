import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../../../providers/settings_provider.dart';
import '../../../utils/icon_engine.dart';

class DynamicAppIcon extends StatefulWidget {
  final double size;
  const DynamicAppIcon({super.key, this.size = 32});

  // Global static cache to prevent asynchronous gap pop-ins on mount
  static String? _cachedSvg;

  @override
  State<DynamicAppIcon> createState() => _DynamicAppIconState();
}

class _DynamicAppIconState extends State<DynamicAppIcon> {
  @override
  void initState() {
    super.initState();
    if (DynamicAppIcon._cachedSvg == null) {
      _loadTemplate();
    }
  }

  Future<void> _loadTemplate() async {
    final data = await rootBundle.loadString('assets/SnapDns.svg');
    DynamicAppIcon._cachedSvg = data;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final svg = DynamicAppIcon._cachedSvg;
    if (svg == null) {
      return SizedBox(width: widget.size, height: widget.size);
    }

    final settings = context.watch<SettingsProvider>();
    final fillHex =
        '#${settings.accentColor.toARGB32().toRadixString(16).substring(2).toLowerCase()}';
    final strokeHex = settings.isDarkMode ? '#bbbbbb' : '#444444';

    final processed = IconEngine.applyColors(svg, fillHex, strokeHex);

    return SvgPicture.string(
      processed,
      width: widget.size,
      height: widget.size,
    );
  }
}
