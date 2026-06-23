import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
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
      // FIX: Aligned daemon kickstart identifier with your official me.vinde.snapdns namespace
      await Process.run('osascript', [
        '-e',
        'do shell script "launchctl kickstart -k system/me.vinde.snapdns" with administrator privileges'
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
    bool isStandardIp = false;

    if (p.primaryDns.isNotEmpty) {
      host = p.primaryDns;
      port = 53;
      isStandardIp = true;
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

    if (isStandardIp) {
      final tcpLatency = await _pingTcp(host, 53);
      if (tcpLatency > 0) {
        return tcpLatency;
      }
      return await _pingUdp(host, 53);
    } else {
      return await _pingTcp(host, port);
    }
  }

  static Future<int> _pingUdp(String host, int port) async {
    RawDatagramSocket? socket;
    try {
      InternetAddress? targetIp = InternetAddress.tryParse(host);
      if (targetIp == null) {
        final lookup = await InternetAddress.lookup(host)
            .timeout(const Duration(milliseconds: 1000));
        if (lookup.isEmpty) return -1;
        targetIp = lookup.first;
      }

      socket = await RawDatagramSocket.bind(
          targetIp.type == InternetAddressType.IPv6
              ? InternetAddress.anyIPv6
              : InternetAddress.anyIPv4,
          0);

      final query = Uint8List.fromList([
        0x24,
        0x1a,
        0x01,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x06,
        0x67,
        0x6f,
        0x6f,
        0x67,
        0x6c,
        0x65,
        0x03,
        0x63,
        0x6f,
        0x6d,
        0x00,
        0x00,
        0x01,
        0x00,
        0x01
      ]);

      final completer = Completer<int>();
      final sw = Stopwatch();

      StreamSubscription? sub;
      sub = socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket!.receive();
          if (dg != null) {
            sw.stop();
            sub?.cancel();
            completer.complete(sw.elapsedMilliseconds);
          }
        }
      });

      sw.start();
      socket.send(query, targetIp, port);

      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!completer.isCompleted) {
          sub?.cancel();
          completer.complete(-1);
        }
      });

      return await completer.future;
    } catch (_) {
      return -1;
    } finally {
      socket?.close();
    }
  }

  static Future<int> _pingTcp(String host, int port) async {
    Socket? s;
    try {
      InternetAddress? targetIp = InternetAddress.tryParse(host);
      if (targetIp == null) {
        final lookup = await InternetAddress.lookup(host)
            .timeout(const Duration(milliseconds: 1000));
        if (lookup.isEmpty) return -1;
        targetIp = lookup.first;
      }

      final sw = Stopwatch();
      sw.start();
      s = await Socket.connect(
        targetIp,
        port,
        timeout: const Duration(milliseconds: 1500),
      );
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    } finally {
      s?.destroy();
    }
  }

  static Future<bool> verifyDnsResolution() async {
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
