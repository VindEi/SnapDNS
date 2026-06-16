import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import '../models/dns_configuration.dart';

class MobileVpnEngine {
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

    // FIX: Core bootstrap builder.
    // If the endpoint is a secure URL/Hostname, we append public bootstrap IPs (1.1.1.1 / 8.8.8.8) to the DNS array.
    // This allows V2Ray to resolve the secure host's domain upon boot, preventing circular lookup deadlocks on mobile.
    final List<dynamic> dnsServers = [dnsEndpoint];
    if (dnsEndpoint.startsWith('https://') ||
        dnsEndpoint.startsWith('tls://')) {
      dnsServers.add('1.1.1.1');
      dnsServers.add('8.8.8.8');
    }

    final String customConfig = jsonEncode({
      "log": {"loglevel": "warning"},
      "dns": {"servers": dnsServers},
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
          "settings": {"domainStrategy": "UseIP"}
        },
        {"protocol": "dns", "tag": "dns-out", "settings": {}}
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
