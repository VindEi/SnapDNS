import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppConstants {
  static const String pipeName = r'\\.\pipe\SnapDns_IPC_v1';
  static const String unixSocketPath = '/tmp/snapdns.sock';

  static const String repoOwner = "VindEi";
  static const String repoName = "SnapDNS";
  static const String appVersion = "1.0.0";

  // We initialize this in main.dart now
  static String appDataPath = "";

  static Future<void> initPaths() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      if (Platform.isWindows) {
        final roaming = Platform.environment['APPDATA'] ?? '';
        appDataPath = p.join(roaming, 'SnapDns');
      } else {
        final home = Platform.environment['HOME'] ?? '';
        appDataPath = p.join(home, '.config', 'snapdns');
      }
    } else {
      // Mobile: Android/iOS
      final dir = await getApplicationDocumentsDirectory();
      appDataPath = p.join(dir.path, 'SnapDns');
    }

    final directory = Directory(appDataPath);
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
  }

  static String get settingsFilePath => p.join(appDataPath, 'settings.json');
  static String get profilesFilePath => p.join(appDataPath, 'profiles.json');
}
