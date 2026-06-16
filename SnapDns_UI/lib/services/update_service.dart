import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants.dart';
import 'tray_manager.dart';

class UpdateInfo {
  final String version;
  final String changelog;
  final String? windowsExeUrl;
  final String releasePageUrl;

  UpdateInfo({
    required this.version,
    required this.changelog,
    this.windowsExeUrl,
    required this.releasePageUrl,
  });
}

class UpdateService {
  static Future<UpdateInfo?> checkUpdate() async {
    try {
      final response = await http.get(
        Uri.parse(
            'https://api.github.com/repos/${AppConstants.repoOwner}/${AppConstants.repoName}/releases/latest'),
        headers: {'User-Agent': 'SnapDns-App'},
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final tag = json['tag_name'] as String;
        final latestVersion = tag.replaceAll('v', '');
        final releasePageUrl = json['html_url'] as String;

        if (_isNewerVersion(AppConstants.appVersion, latestVersion)) {
          String? winExeUrl;

          // Only look for the .exe file for Windows auto-installation
          for (var asset in json['assets']) {
            final name = asset['name'].toString().toLowerCase();
            if (name.endsWith('.exe')) {
              winExeUrl = asset['browser_download_url'] as String;
              break;
            }
          }

          return UpdateInfo(
            version: latestVersion,
            changelog: json['body'] ?? "Minor bug fixes and improvements.",
            windowsExeUrl: winExeUrl,
            releasePageUrl: releasePageUrl,
          );
        }
      }
    } catch (e) {
      debugPrint("Update Check Failed: $e");
    }
    return null;
  }

  static bool _isNewerVersion(String current, String latest) {
    final cParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final lParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final c = i < cParts.length ? cParts[i] : 0;
      final l = i < lParts.length ? lParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }

  static Future<void> performUpdate(BuildContext context, UpdateInfo info,
      Function(double) onProgress) async {
    // 1. WINDOWS: Direct Download & Execution
    if (Platform.isWindows && info.windowsExeUrl != null) {
      try {
        final tempDir = await getTemporaryDirectory();
        final savePath = '${tempDir.path}\\SnapDNS_Update.exe';

        final request = http.Request('GET', Uri.parse(info.windowsExeUrl!));
        final response = await http.Client().send(request);
        final contentLength = response.contentLength ?? 1;

        int bytesDownloaded = 0;
        final file = File(savePath);
        final sink = file.openWrite();

        await response.stream.forEach((chunk) {
          bytesDownloaded += chunk.length;
          sink.add(chunk);
          onProgress(bytesDownloaded / contentLength);
        });

        await sink.flush();
        await sink.close();

        // FIX: Spawn the installer as a completely detached process.
        // This prevents synchronous deadlocks, allowing our Flutter app to terminate and release file locks immediately.
        await Process.start(savePath, [], mode: ProcessStartMode.detached);

        // Shutdown app to allow overwrite
        try {
          await AppTrayManager()
              .hideTray()
              .timeout(const Duration(milliseconds: 200));
        } catch (_) {}
        exit(0);
      } catch (e) {
        debugPrint("Windows Update Failed: $e");
        // Fallback to browser if download fails
        await launchUrl(Uri.parse(info.releasePageUrl),
            mode: LaunchMode.externalApplication);
      }
    }
    // 2. ANDROID / MAC / LINUX: Redirect to Release Page
    else {
      await launchUrl(Uri.parse(info.releasePageUrl),
          mode: LaunchMode.externalApplication);
    }
  }
}
