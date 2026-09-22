import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../core/constants.dart';
import '../services/dns_engine.dart';
import '../storage/profile_storage.dart';
import '../services/system_utils.dart';
import '../utils/dns_intelligence.dart';
import '../models/dns_configuration.dart';
import '../services/tray_manager.dart';
import 'settings_provider.dart';
import 'toast_provider.dart';

class DnsProvider extends ChangeNotifier {
  final ToastProvider _toastProvider;

  DnsProvider(this._toastProvider);

  final DnsEngine _engine = DnsEngine.create();
  Timer? _refreshTimer;
  bool _isRefreshing = false;
  bool _isFlushing = false;

  bool get isDesktop => DnsEngine.isDesktop;

  bool isServiceConnected = false;
  bool isMobileConnected = false;

  String? _manualAdapterId, _autoHardwareId;
  String systemPrimary = "---";
  bool systemIsDoh = false;
  String systemIpv6Status = "OFF";

  DnsConfiguration? _activeMobileConfig;

  final List<DnsConfiguration> _profiles = [];
  List<DnsConfiguration> get profiles => _profiles;
  final List<String> _adapters = [];
  List<String> get adapters => _adapters;

  String smartProviderName = "DISCONNECTED";
  List<String> smartDnsValues = ["---"];

  String get ipv6Summary {
    switch (systemIpv6Status) {
      case "DHCP":
        return "IPv6: DHCP";
      case "STATIC":
        return "IPv6: Static";
      case "BYPASS":
        return "IPv6: Purged";
      default:
        return "IPv6: None";
    }
  }

  Future<void> initialize() async {
    _profiles.addAll(await ProfileStorage.load());
    if (_profiles.isEmpty) await resetToDefaultProfiles();

    if (!isDesktop) {
      try {
        final activeFile =
            File(p.join(AppConstants.appDataPath, 'active_mobile.txt'));
        if (await activeFile.exists()) {
          final savedId = await activeFile.readAsString();
          _activeMobileConfig =
              _profiles.firstWhere((p) => p.id == savedId.trim());
        }
      } catch (_) {}
    }

    await _engine.initialize();
    await refreshStatus();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => refreshStatus());
  }

  String get readableAdapterName =>
      _manualAdapterId ?? _autoHardwareId ?? "AUTOMATIC";

  bool get isSystemDnsSaved {
    if (systemPrimary == "---" || systemPrimary == "AUTO") return true;
    return _profiles.any((p) =>
        p.primaryDns == systemPrimary ||
        p.dohUrl == systemPrimary ||
        p.dotHostname == systemPrimary);
  }

  bool isAdapterSelected(String? id) => _manualAdapterId == id;

  Future<void> refreshStatus() async {
    if (_isRefreshing) return;
    _isRefreshing = true;

    try {
      final state = await _engine.getStatus(_manualAdapterId ?? "");
      isServiceConnected = state.isServiceConnected;

      if (isDesktop) {
        if (isServiceConnected) {
          if (state.adapters.isNotEmpty) {
            _adapters.clear();
            _adapters.addAll(state.adapters);
          }
          _autoHardwareId = state.preferredAdapter;
          if (state.configuration != null) _updateUI(state.configuration!);
        } else {
          _adapters.clear();
          systemPrimary = "---";
          smartDnsValues = ["---"];
          smartProviderName = "SERVICE OFFLINE";

          if (isDesktop) {
            AppTrayManager().updateTooltip("Service offline");
          }
        }
      } else {
        isMobileConnected = state.isMobileConnected;
        if (isMobileConnected) {
          if (_activeMobileConfig != null) {
            _updateUI(_activeMobileConfig!);
          } else {
            systemPrimary = "SECURE DNS";
            smartDnsValues = ["ACTIVE"];
            smartProviderName = "SNAPDNS TUNNEL";
          }
        } else {
          systemPrimary = "AUTO";
          smartDnsValues = ["AUTO"];
          smartProviderName = "SYSTEM DEFAULT (DHCP)";
        }
      }
    } catch (_) {
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  void _updateUI(DnsConfiguration cfg) {
    systemIsDoh = cfg.primaryDns == "127.0.0.1";
    systemPrimary = systemIsDoh
        ? (cfg.dohUrl.isNotEmpty ? cfg.dohUrl : cfg.dotHostname)
        : (cfg.primaryDns.isEmpty || cfg.primaryDns == "DHCP"
            ? "AUTO"
            : cfg.primaryDns);

    if (systemIsDoh) {
      systemIpv6Status = "BYPASS";
    } else if (cfg.ipv6Primary == "DHCP") {
      systemIpv6Status = "DHCP";
    } else if (cfg.ipv6Primary.isNotEmpty) {
      systemIpv6Status = "STATIC";
    } else {
      systemIpv6Status = "OFF";
    }

    if (systemPrimary == "AUTO") {
      smartProviderName = "SYSTEM DEFAULT (DHCP)";
      if (isDesktop) {
        AppTrayManager().updateTooltip("System Default (DHCP)");
      }
    } else {
      smartProviderName =
          cfg.name == "DHCP" ? "SYSTEM DEFAULT (DHCP)" : "CUSTOM RESOLVER";
      String protocol = "IP";

      if (systemIsDoh) {
        protocol = cfg.dohUrl.isNotEmpty ? "DoH" : "DoT";
      }

      for (var p in _profiles) {
        if ((systemIsDoh &&
                (p.dohUrl == systemPrimary ||
                    p.dotHostname == systemPrimary)) ||
            (!systemIsDoh && p.primaryDns == systemPrimary)) {
          smartProviderName = p.name.toUpperCase();
          if (p.dohUrl.isNotEmpty && systemIsDoh) {
            protocol = "DoH";
          } else if (p.dotHostname.isNotEmpty && systemIsDoh) {
            protocol = "DoT";
          } else if (p.ipv6Primary.isNotEmpty) {
            protocol = "IPv6";
          } else {
            protocol = "IPv4";
          }
          break;
        }
      }

      if (isDesktop) {
        final String displayName = smartProviderName == "CUSTOM RESOLVER"
            ? "Custom"
            : smartProviderName[0] +
                smartProviderName.substring(1).toLowerCase();
        AppTrayManager().updateTooltip("$displayName ($protocol)");
      }
    }

    String cleanDisplayValue = systemPrimary;
    if (systemIsDoh) {
      try {
        final uri = Uri.tryParse(cleanDisplayValue);
        if (uri != null && uri.host.isNotEmpty) {
          cleanDisplayValue = uri.host;
        } else {
          cleanDisplayValue = cleanDisplayValue
              .replaceFirst("https://", "")
              .replaceFirst("http://", "")
              .split("/")
              .first;
        }
      } catch (_) {}
    }

    smartDnsValues = [cleanDisplayValue];
  }

  Future<void> connectDns(
      DnsConfiguration config, SettingsProvider settings) async {
    _toastProvider.showToast("APPLYING...");
    final res = await _engine.connect(config, readableAdapterName,
        disableIpv6: settings.disableIpv6);

    if (isDesktop) {
      if (res.success) {
        if (settings.autoFlush) await flushDns();
        if (settings.verifyConnection) {
          _toastProvider.showToast("VERIFYING...");
          bool works = await SystemUtils.verifyDnsResolution();
          _toastProvider
              .showToast(works ? "CONNECTED & VERIFIED" : "DNS NO RESOLUTION");
        } else {
          _toastProvider.showToast("SUCCESS");
        }
      } else {
        _toastProvider.showToast("FAILED: ${res.message}");
      }
    } else {
      if (res.success) {
        _activeMobileConfig = config;
        _updateUI(config);

        try {
          final activeFile =
              File(p.join(AppConstants.appDataPath, 'active_mobile.txt'));
          await activeFile.writeAsString(config.id, flush: true);
        } catch (_) {}
      }
      _toastProvider.showToast(res.message);
    }
    await refreshStatus();
  }

  void resetToDefaults() async {
    _toastProvider.showToast("RESETTING...");
    bool success = await _engine.disconnect(readableAdapterName);
    if (success) {
      if (!isDesktop) {
        _activeMobileConfig = null;
        systemPrimary = "AUTO";
        smartDnsValues = ["AUTO"];
        smartProviderName = "SYSTEM DEFAULT (DHCP)";

        try {
          final activeFile =
              File(p.join(AppConstants.appDataPath, 'active_mobile.txt'));
          if (await activeFile.exists()) {
            await activeFile.delete();
          }
        } catch (_) {}

        _toastProvider.showToast("VPN DISCONNECTED");
      } else {
        _toastProvider.showToast("DHCP RESTORED");

        if (isDesktop) {
          AppTrayManager().updateTooltip("System Default (DHCP)");
        }
      }
      refreshStatus();
    } else {
      _toastProvider.showToast("FAILED TO DISCONNECT");
    }
  }

  Future<void> flushDns() async {
    if (_isFlushing) return;
    _isFlushing = true;

    try {
      if (isDesktop) {
        _toastProvider.showToast("FLUSHING...");
        bool success = await _engine.flush();
        if (success) {
          _toastProvider.showToast("DNS CACHE FLUSHED");
        } else {
          _toastProvider.showToast("FLUSH FAILED (SERVICE OFFLINE)");
        }
      } else if (_activeMobileConfig != null) {
        _toastProvider.showToast("FLUSHING...");
        await _engine.disconnect("");
        await _engine.connect(_activeMobileConfig!, "");
        _toastProvider.showToast("VPN RESTARTED (CACHE FLUSHED)");
      } else {
        _toastProvider.showToast("NO ACTIVE TUNNEL");
      }
    } finally {
      _isFlushing = false;
    }
  }

  Future<void> restartService() async {
    if (isDesktop) {
      _toastProvider.showToast("UAC PROMPT...");

      try {
        await SystemUtils.restartService();
      } catch (e) {
        debugPrint("DEBUG: [Service] Restart elevation denied: $e");
        _toastProvider.showToast("ACCESS DENIED");
      }
    }
  }

  int importProfilesFromData(String data) {
    final imported = DnsIntelligence.parseImportData(data);
    if (imported.isEmpty) {
      _toastProvider.showToast("NO VALID DATA FOUND");
      return 0;
    }

    int addedCount = 0;
    int updatedCount = 0;

    for (var profile in imported) {
      final index = _profiles.indexWhere((p) => p.id == profile.id);
      if (index != -1) {
        _profiles[index] = profile;
        updatedCount++;
      } else {
        final exists = _profiles.any((p) =>
            p.name == profile.name &&
            p.primaryDns == profile.primaryDns &&
            p.dohUrl == profile.dohUrl &&
            p.dotHostname == profile.dotHostname);

        if (!exists) {
          _profiles.add(profile);
          addedCount++;
        }
      }
    }

    ProfileStorage.save(_profiles);
    notifyListeners();

    final total = addedCount + updatedCount;
    if (total == 0) {
      _toastProvider.showToast("PROFILES ALREADY EXIST");
    } else {
      _toastProvider.showToast(
          total == 1 ? "IMPORTED 1 PROFILE" : "IMPORTED $total PROFILES");
    }

    return total;
  }

  void smartImport(DnsConfiguration? suggested) {
    if (suggested == null) {
      _toastProvider.showToast("NO DATA FOUND");
      return;
    }
    addOrUpdateProfile(suggested);
    _toastProvider.showToast("IMPORTED");
  }

  DnsConfiguration getSystemAsConfig() => DnsConfiguration(
        name: "Live Backup",
        primaryDns: systemIsDoh ? "" : systemPrimary,
        dohUrl: systemIsDoh ? systemPrimary : "",
      );

  Future<void> refreshLatencies() async {
    final futures = _profiles.map((p) async {
      p.latencyMs = await SystemUtils.checkLatency(p);
    }).toList();
    await Future.wait(futures);
    notifyListeners();
  }

  Future<void> resetToDefaultProfiles() async {
    _profiles.clear();
    _profiles.addAll(DnsIntelligence.defaultProfiles);
    ProfileStorage.save(_profiles);
    notifyListeners();
  }

  void setSelectedAdapter(String? id) {
    _manualAdapterId = id;
    refreshStatus();
  }

  void copyToClipboard(String t) {
    SystemUtils.copyToClipboard(t);
    _toastProvider.showToast("COPIED");
  }

  void addOrUpdateProfile(DnsConfiguration c) {
    final i = _profiles.indexWhere((p) => p.id == c.id);
    if (i != -1) {
      _profiles[i] = c;
    } else {
      _profiles.add(c);
    }
    ProfileStorage.save(_profiles);
    notifyListeners();
  }

  void deleteProfile(DnsConfiguration c) {
    _profiles.removeWhere((p) => p.id == c.id);
    ProfileStorage.save(_profiles);
    notifyListeners();
  }

  void reorderProfiles(int o, int n) {
    _profiles.insert(n, _profiles.removeAt(o));
    ProfileStorage.save(_profiles);
    notifyListeners();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
