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
      if (!iconDir.existsSync()) {
        iconDir.createSync(recursive: true);
      }

      final fillHex =
          '#${accentColor.toARGB32().toRadixString(16).substring(2).toLowerCase()}';
      final strokeHex = isDark ? '#bbbbbb' : '#444444';

      String processed = applyColors(rawSvg, fillHex, strokeHex);

      if (Platform.isWindows) {
        // FIX: Utilize hashed names to prevent write violations on OS-locked files during runtime theme transitions.
        final String cleanHex = fillHex.replaceFirst('#', '');
        final String iconName =
            'app_icon_${cleanHex}_${isDark ? "dark" : "light"}.ico';
        final String icoPath = p.join(iconDirPath, iconName);

        if (!File(icoPath).existsSync()) {
          final Uint8List icoBytes =
              await _generateProperIco(processed, [16, 24, 32, 48, 64, 256]);
          File(icoPath).writeAsBytesSync(icoBytes, flush: true);

          // Safely prune old, unlocked icons in the background to prevent storage leaks
          try {
            final List<FileSystemEntity> files = iconDir.listSync();
            for (var file in files) {
              if (file is File &&
                  p.basename(file.path) != iconName &&
                  p.extension(file.path) == '.ico') {
                await file.delete();
              }
            }
          } catch (_) {
            // Ignore locked deletions; they will be removed on subsequent sweeps when released
          }
        }

        return {'tray': icoPath, 'taskbar': icoPath};
      } else {
        final String pngPath =
            await _renderPng(processed, 256, 'app_icon.png', iconDirPath);
        return {'tray': pngPath, 'taskbar': pngPath};
      }
    } catch (e) {
      debugPrint("DEBUG: [IconEngine] Generation Error: $e");
      return null;
    }
  }

  static Future<Uint8List> _generateProperIco(
      String svg, List<int> sizes) async {
    final List<Uint8List> imageData = [];

    final SvgLoader loader = SvgStringLoader(svg);
    final PictureInfo pictureInfo = await vg.loadPicture(loader, null);

    for (int dim in sizes) {
      final ui.PictureRecorder rec = ui.PictureRecorder();
      final Canvas c = Canvas(rec);
      c.scale(dim / pictureInfo.size.width);
      c.drawPicture(pictureInfo.picture);
      final ui.Image rendered = await rec.endRecording().toImage(dim, dim);

      if (dim == 256) {
        final byteData =
            await rendered.toByteData(format: ui.ImageByteFormat.png);
        imageData.add(byteData!.buffer.asUint8List());
      } else {
        final byteData =
            await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
        final rgba = byteData!.buffer.asUint8List();

        int xorSize = dim * dim * 4;
        int andRowBytes = ((dim + 31) ~/ 32) * 4;
        int andSize = andRowBytes * dim;

        final dib = Uint8List(40 + xorSize + andSize);
        final bd = ByteData.view(dib.buffer);

        bd.setUint32(0, 40, Endian.little);
        bd.setUint32(4, dim, Endian.little);
        bd.setUint32(8, dim * 2, Endian.little);
        bd.setUint16(12, 1, Endian.little);
        bd.setUint16(14, 32, Endian.little);
        bd.setUint32(16, 0, Endian.little);
        bd.setUint32(20, xorSize + andSize, Endian.little);
        bd.setUint32(24, 0, Endian.little);
        bd.setUint32(28, 0, Endian.little);
        bd.setUint32(32, 0, Endian.little);
        bd.setUint32(36, 0, Endian.little);

        int offset = 40;
        for (int y = dim - 1; y >= 0; y--) {
          for (int x = 0; x < dim; x++) {
            int srcIndex = (y * dim + x) * 4;
            int r = rgba[srcIndex];
            int g = rgba[srcIndex + 1];
            int b = rgba[srcIndex + 2];
            int a = rgba[srcIndex + 3];

            dib[offset++] = (b * a) ~/ 255;
            dib[offset++] = (g * a) ~/ 255;
            dib[offset++] = (r * a) ~/ 255;
            dib[offset++] = a;
          }
        }

        int andOffset = 40 + xorSize;
        for (int y = dim - 1; y >= 0; y--) {
          int byteVal = 0;
          int bytePixelCount = 0;
          int bytesWrittenInRow = 0;

          for (int x = 0; x < dim; x++) {
            int srcIndex = (y * dim + x) * 4;
            int a = rgba[srcIndex + 3];

            int bit = (a < 128) ? 1 : 0;
            int bitPos = 7 - bytePixelCount;
            byteVal |= (bit << bitPos);
            bytePixelCount++;

            if (bytePixelCount == 8 || x == dim - 1) {
              dib[andOffset + bytesWrittenInRow] = byteVal;
              bytesWrittenInRow++;
              byteVal = 0;
              bytePixelCount = 0;
            }
          }
          while (bytesWrittenInRow < andRowBytes) {
            dib[andOffset + bytesWrittenInRow] = 0;
            bytesWrittenInRow++;
          }
          andOffset += andRowBytes;
        }

        imageData.add(dib);
      }
    }

    int numImages = sizes.length;
    int headerSize = 6 + (16 * numImages);
    int totalSize = headerSize;
    for (var d in imageData) {
      totalSize += d.length;
    }

    final result = Uint8List(totalSize);
    final bd = ByteData.view(result.buffer);

    bd.setUint16(0, 0, Endian.little);
    bd.setUint16(2, 1, Endian.little);
    bd.setUint16(4, numImages, Endian.little);

    int imageOffset = headerSize;
    for (int i = 0; i < numImages; i++) {
      int dim = sizes[i];
      int dirOffset = 6 + (16 * i);
      bd.setUint8(dirOffset + 0, dim == 256 ? 0 : dim);
      bd.setUint8(dirOffset + 1, dim == 256 ? 0 : dim);
      bd.setUint8(dirOffset + 2, 0);
      bd.setUint8(dirOffset + 3, 0);
      bd.setUint16(dirOffset + 4, 1, Endian.little);
      bd.setUint16(dirOffset + 6, 32, Endian.little);
      bd.setUint32(dirOffset + 8, imageData[i].length, Endian.little);
      bd.setUint32(dirOffset + 12, imageOffset, Endian.little);

      result.setAll(imageOffset, imageData[i]);
      imageOffset += imageData[i].length;
    }

    return result;
  }

  static Future<String> _renderPng(
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

    final file = File(p.join(folder, name));
    file.writeAsBytesSync(byteData!.buffer.asUint8List(), flush: true);

    return file.absolute.path.replaceAll('/', Platform.isWindows ? '\\' : '/');
  }
}
