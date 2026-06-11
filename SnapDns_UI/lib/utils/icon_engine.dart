import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;
import '../core/constants.dart';

class IconEngine {
  static String applyColors(String rawSvg, String fillHex, String strokeHex) {
    return rawSvg
        .replaceAll(
            RegExp(r'fill="[^"]+"', caseSensitive: false), 'fill="$fillHex"')
        .replaceAll(RegExp(r'stroke="[^"]+"', caseSensitive: false),
            'stroke="$strokeHex"');
  }

  static Future<Map<String, String>?> generateSystemIcons({
    required String rawSvg,
    required Color accentColor,
    required bool isDark,
  }) async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return null;
    }

    try {
      final String iconDirPath = p.join(AppConstants.appDataPath, 'icons');
      final Directory iconDir = Directory(iconDirPath);
      if (!iconDir.existsSync()) iconDir.createSync(recursive: true);

      final fillHex =
          '#${accentColor.toARGB32().toRadixString(16).substring(2).toLowerCase()}';
      final strokeHex = isDark ? '#bbbbbb' : '#444444';

      String processed = applyColors(rawSvg, fillHex, strokeHex);

      final String ext = Platform.isWindows ? 'ico' : 'png';

      // FIX: Static filenames instead of timestamps. This automatically overwrites and prevents bloat.
      final trayPath =
          await _render(processed, 32, 'tray_icon.$ext', iconDirPath);
      final taskbarPath =
          await _render(processed, 256, 'task_icon.$ext', iconDirPath);

      return {'tray': trayPath, 'taskbar': taskbarPath};
    } catch (e) {
      debugPrint("DEBUG: [IconEngine] Generation Error: $e");
      return null;
    }
  }

  static Future<String> _render(
      String svg, double dim, String name, String folder) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final SvgLoader loader = SvgStringLoader(svg);
    final PictureInfo pictureInfo = await vg.loadPicture(loader, null);

    canvas.scale(dim / pictureInfo.size.width);
    canvas.drawPicture(pictureInfo.picture);

    final ui.Image img =
        await recorder.endRecording().toImage(dim.toInt(), dim.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    final Uint8List finalBytes =
        Platform.isWindows ? _convertToIco(pngBytes, dim.toInt()) : pngBytes;

    final file = File(p.join(folder, name));
    file.writeAsBytesSync(finalBytes, flush: true);

    return file.absolute.path.replaceAll('/', Platform.isWindows ? '\\' : '/');
  }

  static Uint8List _convertToIco(Uint8List pngBytes, int size) {
    final bd = ByteData(22 + pngBytes.length);
    bd.setUint16(0, 0, Endian.little);
    bd.setUint16(2, 1, Endian.little);
    bd.setUint16(4, 1, Endian.little);
    bd.setUint8(6, size >= 256 ? 0 : size);
    bd.setUint8(7, size >= 256 ? 0 : size);
    bd.setUint8(8, 0);
    bd.setUint8(9, 0);
    bd.setUint16(10, 1, Endian.little);
    bd.setUint16(12, 32, Endian.little);
    bd.setUint32(14, pngBytes.length, Endian.little);
    bd.setUint32(18, 22, Endian.little);

    final result = bd.buffer.asUint8List();
    result.setAll(22, pngBytes);
    return result;
  }
}
