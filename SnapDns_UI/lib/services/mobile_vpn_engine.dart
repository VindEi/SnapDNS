import 'dart:convert';
import 'package:flutter/services.dart'; // Restored import
import 'package:flutter/foundation.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import '../models/dns_configuration.dart';

class MobileVpnEngine {
  // Restored MethodChannel
  static const _channel = MethodChannel("me.vinde.snapdns/channel");
  static String _currentState = "DISCONNECTED";

  static final FlutterV2ray _v2ray = FlutterV2ray(
    onStatusChanged: (V2RayStatus status) {
      _currentState = status.state;
      debugPrint("DEBUG: [Vpn] Connection State Changed: ${status.state}");
    },
  );

  static Future<void> initialize() async {
    await _v2ray.initializeV2Ray();
  }

  // Restored Always-On VPN Settings Redirector
  static Future<void> openVpnSettings() async {
    try {
      await _channel.invokeMethod("openVpnSettings");
    } catch (e) {
      debugPrint("DEBUG: [Vpn] Failed to open VPN Settings: $e");
    }
  }

  static Future<bool> startDnsTunnel(DnsConfiguration config) async {
    String dnsEndpoint;
    if (config.dohUrl.isNotEmpty) {
      dnsEndpoint = config.dohUrl;
    } else if (config.dotHostname.isNotEmpty) {
      dnsEndpoint = "tls://${config.dotHostname}";
    } else {
      dnsEndpoint = config.primaryDns;
    }

    if (dnsEndpoint.isEmpty) return false;

    // Advanced V2Ray local DNS proxy configuration with blind-parser bypass
    final String customConfig = jsonEncode({
      "log": {"loglevel": "warning"},
      "dns": {
        "servers": [dnsEndpoint]
      },
      "inbounds": [
        {
          "port": 10808,
          "protocol": "socks",
          "settings": {"auth": "noauth", "udp": true, "ip": "127.0.0.1"},
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls"]
          }
        }
      ],
      "outbounds": [
        {
          "protocol": "freedom",
          "tag": "direct",
          "settings": {
            "domainStrategy": "UseIP",
            "servers": [
              {"address": "127.0.0.1", "port": 1}
            ]
          }
        },
        {
          "protocol": "dns",
          "tag": "dns-out",
          "settings": {
            "servers": [
              {"address": "127.0.0.1", "port": 1}
            ]
          }
        }
      ],
      "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
          {"type": "field", "port": "53", "outboundTag": "dns-out"},
          {"type": "field", "network": "tcp,udp", "outboundTag": "direct"}
        ]
      }
    });

    debugPrint("DEBUG: [Vpn] Starting Tunnel with DNS: $dnsEndpoint");

    if (await _v2ray.requestPermission()) {
      // Sync this configuration to Android SharedPreferences for the Quick Settings Tile
      try {
        await _channel.invokeMethod("saveLastConfig", {"config": customConfig});
      } catch (e) {
        debugPrint("DEBUG: [Vpn] Failed to save config to native prefs: $e");
      }

      await _v2ray.startV2Ray(
        remark: "SnapDns Resolver",
        config: customConfig,
        proxyOnly: false,
      );
      return true;
    }

    return false;
  }

  static Future<void> stopTunnel() async {
    await _v2ray.stopV2Ray();
    debugPrint("DEBUG: [Vpn] Tunnel Stop requested.");
  }

  static Future<bool> isConnected() async {
    return _currentState == "CONNECTED";
  }
}
