import 'dart:io';
import 'package:flutter/services.dart';

class SystemUtils {
  static Future<void> restartService() async {
    if (Platform.isWindows) {
      await Process.run('powershell', [
        '-Command',
        'Start-Process cmd -ArgumentList "/c net stop SnapDnsService & net start SnapDnsService" -Verb RunAs -WindowStyle Hidden',
      ]);
    } else if (Platform.isLinux || Platform.isMacOS) {
      // Assuming systemd for Linux or general shell for macOS
      await Process.run('sudo', ['systemctl', 'restart', 'snapdns']);
    }
  }

  static void copyToClipboard(String text) {
    if (text.isNotEmpty && text != "---") {
      Clipboard.setData(ClipboardData(text: text));
    }
  }

  static Future<int> checkLatency(String ip) async {
    if (ip.isEmpty || ip == "AUTO" || ip == "DHCP") return -1;
    Socket? s;
    try {
      final sw = Stopwatch()..start();
      s = await Socket.connect(
        ip,
        53,
        timeout: const Duration(milliseconds: 1500),
      );
      final ms = sw.elapsedMilliseconds;
      return ms;
    } catch (_) {
      return -1;
    } finally {
      s?.destroy();
    }
  }

  // --- NEW: Cross-Platform DNS Verification ---
  static Future<bool> verifyDnsResolution() async {
    try {
      // We look up a common domain. If the DNS is broken, this throws or returns empty.
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.address.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
