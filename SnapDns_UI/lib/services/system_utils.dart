import 'dart:io';
import 'package:flutter/services.dart';
import '../models/dns_configuration.dart';

class SystemUtils {
  static Future<void> restartService() async {
    if (Platform.isWindows) {
      await Process.run('powershell', [
        '-Command',
        'Start-Process cmd -ArgumentList "/c net stop SnapDnsService & net start SnapDnsService" -Verb RunAs -WindowStyle Hidden',
      ]);
    } else if (Platform.isLinux) {
      await Process.run('pkexec', ['systemctl', 'restart', 'snapdns']);
    } else if (Platform.isMacOS) {
      await Process.run('osascript', [
        '-e',
        'do shell script "launchctl kickstart -k system/com.vindei.snapdns" with administrator privileges'
      ]);
    }
  }

  static void copyToClipboard(String text) {
    if (text.isNotEmpty && text != "---") {
      Clipboard.setData(ClipboardData(text: text));
    }
  }

  static Future<int> checkLatency(DnsConfiguration p) async {
    String host = "";
    int port = 53;

    if (p.primaryDns.isNotEmpty) {
      host = p.primaryDns;
      port = 53;
    } else if (p.dotHostname.isNotEmpty) {
      host = p.dotHostname;
      port = 853;
    } else if (p.dohUrl.isNotEmpty) {
      try {
        final uri = Uri.parse(p.dohUrl);
        host = uri.host;
        port = uri.scheme == 'https' ? 443 : 80;
      } catch (_) {
        return -1;
      }
    }

    if (host.isEmpty || host == "AUTO" || host == "DHCP") return -1;
    Socket? s;
    try {
      final sw = Stopwatch()..start();
      s = await Socket.connect(
        host,
        port,
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

  static Future<bool> verifyDnsResolution() async {
    // FIX: Introduce a 500ms delay to allow the operating system's internal resolver
    // to synchronize and register the new local loopback/proxy endpoint before querying
    await Future.delayed(const Duration(milliseconds: 500));

    final hosts = ['one.one.one.one', 'dns.google', 'google.com'];
    for (var host in hosts) {
      try {
        final result = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 2));
        if (result.isNotEmpty && result.first.address.isNotEmpty) {
          return true;
        }
      } catch (_) {
        // Fallback to the next host on failure
      }
    }
    return false;
  }
}
