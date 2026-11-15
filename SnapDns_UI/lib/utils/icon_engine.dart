import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;
import '../core/constants.dart';

abstract class _Win32IconHelper {
  static final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');

  static final int Function(Pointer<Utf16>, Pointer<Utf16>) findWindowW =
      _user32.lookupFunction<
          IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
          int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');

  static final int Function(int) getSystemMetrics = _user32.lookupFunction<
      Int32 Function(Int32), int Function(int)>('GetSystemMetrics');

  static final int Function(int, Pointer<Utf16>, int, int, int, int)
      loadImageW = _user32.lookupFunction<
          IntPtr Function(
              IntPtr, Pointer<Utf16>, Uint32, Int32, Int32, Uint32),
          int Function(
              int, Pointer<Utf16>, int, int, int, int)>('LoadImageW');

  static final int Function(int, int, int, int) sendMessageW =
      _user32.lookupFunction<IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr),
          int Function(int, int, int, int)>('SendMessageW');
}

const int _smCxIcon = 11;
const int _smCyIcon = 12;
const int _smCxSmIcon = 49;
const int _smCySmIcon = 50;
const int _imageIcon = 1;
const int _lrLoadFromFile = 0x00000010;
const int _wmSetIcon = 0x0080;
const int _iconSmall = 0;
const int _iconBig = 1;

class IconEngine {
  static const List<int> standardIconSizes = [
    256,
    128,
    64,
    48,
    40,
    32,
    24,
    20,
    16
  ];

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
      final strokeHex = fillHex;

      String processed = applyColors(rawSvg, fillHex, strokeHex);

      if (Platform.isWindows) {
        final String cleanHex = fillHex.replaceFirst('#', '');
        final String iconName =
            'app_icon_${cleanHex}_${isDark ? "dark" : "light"}_v210.ico';
        final String icoPath = p.join(iconDirPath, iconName);

        if (!File(icoPath).existsSync()) {
          final Uint8List icoBytes =
              await _generateProperIco(processed, standardIconSizes);
          File(icoPath).writeAsBytesSync(icoBytes, flush: true);

          try {
            final List<FileSystemEntity> files = iconDir.listSync();
            for (var file in files) {
              if (file is File &&
                  p.basename(file.path) != iconName &&
                  p.extension(file.path) == '.ico') {
                await file.delete();
              }
            }
          } catch (_) {}
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

  static void applyWindowIconNative(String icoPath) {
    if (!Platform.isWindows) return;
    try {
      final title1 = 'SnapDNS'.toNativeUtf16();
      final title2 = 'SnapDNS '.toNativeUtf16();
      int hWnd = _Win32IconHelper.findWindowW(nullptr, title1);
      if (hWnd == 0) hWnd = _Win32IconHelper.findWindowW(nullptr, title2);
      malloc.free(title1);
      malloc.free(title2);

      if (hWnd != 0) {
        final pathPtr = icoPath.toNativeUtf16();
        final cxBig = _Win32IconHelper.getSystemMetrics(_smCxIcon);
        final cyBig = _Win32IconHelper.getSystemMetrics(_smCyIcon);
        final cxSm = _Win32IconHelper.getSystemMetrics(_smCxSmIcon);
        final cySm = _Win32IconHelper.getSystemMetrics(_smCySmIcon);

        final hBig = _Win32IconHelper.loadImageW(
            0, pathPtr, _imageIcon, cxBig, cyBig, _lrLoadFromFile);
        if (hBig != 0) {
          _Win32IconHelper.sendMessageW(hWnd, _wmSetIcon, _iconBig, hBig);
        }
        final hSm = _Win32IconHelper.loadImageW(
            0, pathPtr, _imageIcon, cxSm, cySm, _lrLoadFromFile);
        if (hSm != 0) {
          _Win32IconHelper.sendMessageW(hWnd, _wmSetIcon, _iconSmall, hSm);
        }
        malloc.free(pathPtr);
      }
    } catch (e) {
      debugPrint("DEBUG: [IconNative] Apply Error: $e");
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

      final byteData =
          await rendered.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        imageData.add(byteData.buffer.asUint8List());
      }
    }

    int numImages = imageData.length;
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
