import 'dart:io';
import 'package:flutter/services.dart';
import '../models/dns_configuration.dart';

class MobileVpnEngine {
  static const _channel = MethodChannel("me.vinde.snapdns/channel");
  static bool _isConnected = false;

  static Future<void> initialize() async {}

  static Future<void> openVpnSettings() async {
    try {
      await _channel.invokeMethod("openVpnSettings");
    } catch (_) {}
  }

  static Future<bool> startDnsTunnel(DnsConfiguration config) async {
    try {
      String hostName = "";

      if (config.dohUrl.isNotEmpty) {
        try {
          hostName = Uri.parse(config.dohUrl).host;
        } catch (_) {}
      } else if (config.dotHostname.isNotEmpty) {
        hostName = config.dotHostname;
      }

      final List<String> resolvedIps = [];

      if (hostName.isNotEmpty) {
        try {
          final lookup = await InternetAddress.lookup(hostName)
              .timeout(const Duration(seconds: 2));
          if (lookup.isNotEmpty) {
            resolvedIps.addAll(lookup.map((e) => e.address));
          }
        } catch (_) {
          // Fallback handled on socket level
        }
      }

      final bool success = await _channel.invokeMethod("startVpn", {
        "primaryDns":
            config.primaryDns.isNotEmpty ? config.primaryDns : "1.1.1.1",
        "secondaryDns":
            config.secondaryDns.isNotEmpty ? config.secondaryDns : null,
        "privateDns": config.dotHostname.isNotEmpty ? config.dotHostname : null,
        "dohUrl": config.dohUrl.isNotEmpty ? config.dohUrl : null,
        "hostName": hostName.isNotEmpty ? hostName : null,
        "resolvedIps": resolvedIps.isNotEmpty ? resolvedIps : null,
      });

      _isConnected = success;
      return success;
    } catch (e) {
      _isConnected = false;
      return false;
    }
  }

  static Future<void> stopTunnel() async {
    try {
      await _channel.invokeMethod("stopVpn");
      _isConnected = false;
    } catch (_) {}
  }

  static Future<bool> isConnected() async {
    return _isConnected;
  }
}
