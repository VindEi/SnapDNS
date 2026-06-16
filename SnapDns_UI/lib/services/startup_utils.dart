import 'dart:io';
import 'package:path/path.dart' as p;

class StartupUtils {
  static const String appName = "SnapDns";

  static Future<void> toggle(bool enabled, {bool launchHidden = false}) async {
    if (Platform.isWindows) {
      await _toggleWindows(enabled, launchHidden);
    } else if (Platform.isLinux) {
      await _toggleLinux(enabled, launchHidden);
    } else if (Platform.isMacOS) {
      await _toggleMacOS(enabled, launchHidden);
    }
  }

  static Future<void> _toggleWindows(bool enabled, bool launchHidden) async {
    final keyPath = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

    if (enabled) {
      String path = Platform.resolvedExecutable;
      if (launchHidden) {
        path = '"$path" --minimized';
      } else {
        path = '"$path"';
      }

      await Process.run('reg',
          ['add', keyPath, '/v', appName, '/t', 'REG_SZ', '/d', path, '/f']);
    } else {
      await Process.run('reg', ['delete', keyPath, '/v', appName, '/f']);
    }
  }

  static Future<void> _toggleLinux(bool enabled, bool launchHidden) async {
    final home = Platform.environment['HOME'];
    if (home == null) return;

    final dir = Directory(p.join(home, '.config', 'autostart'));
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final file = File(p.join(dir.path, '${appName.toLowerCase()}.desktop'));

    if (enabled) {
      String exec = Platform.resolvedExecutable;
      if (launchHidden) exec = '$exec --minimized';

      final content = '''
[Desktop Entry]
Type=Application
Name=$appName
Comment=SnapDns DNS Manager
Exec=$exec
Terminal=false
X-GNOME-Autostart-enabled=true
''';
      await file.writeAsString(content);
    } else {
      if (await file.exists()) await file.delete();
    }
  }

  static Future<void> _toggleMacOS(bool enabled, bool launchHidden) async {
    final home = Platform.environment['HOME'];
    if (home == null) return;

    final dir = Directory(p.join(home, 'Library', 'LaunchAgents'));
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final file =
        File(p.join(dir.path, 'com.vindei.${appName.toLowerCase()}.plist'));

    if (enabled) {
      String exec = Platform.resolvedExecutable;
      // FIX: Clean launch argument XML generation
      final argsBlock =
          launchHidden ? '\n        <string>--minimized</string>' : '';

      final content = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.vindei.${appName.toLowerCase()}</string>
    <key>ProgramArguments</key>
    <array>
        <string>$exec</string>$argsBlock
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
''';
      await file.writeAsString(content);
    } else {
      if (await file.exists()) await file.delete();
    }
  }
}
