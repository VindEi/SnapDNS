import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppConstants {
  static const String pipeName = r'\\.\pipe\SnapDns_IPC_v1';

  static const String unixSocketPath = '/var/run/snapdns.sock';

  static const String repoOwner = "VindEi";
  static const String repoName = "SnapDNS";
  static const String appVersion = "2.1.0";
  static const String defaultAccentColor = "#00C8C8";

  static String appDataPath = "";

  static Future<void> initPaths() async {
    try {
      if (Platform.isWindows) {
        final roaming = Platform.environment['APPDATA'] ?? '';
        appDataPath = p.join(roaming, 'SnapDns');
      } else if (Platform.isMacOS) {
        final dir = await getApplicationSupportDirectory();
        appDataPath = dir.path;
      } else if (Platform.isLinux) {
        final home = Platform.environment['HOME'] ?? '';
        appDataPath = home.isNotEmpty
            ? p.join(home, '.config', 'snapdns')
            : '/tmp/snapdns';
      } else {
        final dir = await getApplicationDocumentsDirectory();
        appDataPath = p.join(dir.path, 'SnapDns');
      }
    } catch (_) {
      appDataPath = '/tmp/snapdns';
    }

    final directory = Directory(appDataPath);
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
  }

  static String get settingsFilePath => p.join(appDataPath, 'settings.json');
  static String get profilesFilePath => p.join(appDataPath, 'profiles.json');
  static String get activeMobileFilePath => p.join(appDataPath, 'active_mobile.txt');
  static String get publicDnsCacheFilePath => p.join(appDataPath, 'public_dns_cache.json');
}
