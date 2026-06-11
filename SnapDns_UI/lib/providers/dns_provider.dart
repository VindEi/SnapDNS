import 'dart:async';
import 'package:flutter/material.dart';
import '../services/dns_engine.dart';
import '../storage/profile_storage.dart';
import '../services/system_utils.dart';
import '../utils/dns_intelligence.dart';
import '../services/toast_service.dart';
import '../models/dns_configuration.dart';
import 'settings_provider.dart';

class DnsProvider extends ChangeNotifier {
  final DnsEngine _engine = DnsEngine.create();
  Timer? _refreshTimer;

  bool get isDesktop => DnsEngine.isDesktop;

  bool isServiceConnected = false;
  bool isMobileConnected = false;

  String? _manualAdapterId, _autoHardwareId;
  String systemPrimary = "---";
  bool systemIsDoh = false;

  DnsConfiguration? _activeMobileConfig;

  final List<DnsConfiguration> _profiles = [];
  List<DnsConfiguration> get profiles => _profiles;
  final List<String> _adapters = [];
  List<String> get adapters => _adapters;

  String smartProviderName = "DISCONNECTED";
  List<String> smartDnsValues = ["---"];

  Future<void> initialize() async {
    _profiles.addAll(await ProfileStorage.load());
    if (_profiles.isEmpty) await resetToDefaultProfiles();
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
    final state = await _engine.getStatus(_manualAdapterId ?? "");
    isServiceConnected = state.isServiceConnected;

    if (isDesktop) {
      if (state.adapters.isNotEmpty) {
        _adapters.clear();
        _adapters.addAll(state.adapters);
      }
      _autoHardwareId = state.preferredAdapter;
      if (state.configuration != null) _updateUI(state.configuration!);
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
        smartProviderName = "DISCONNECTED";
      }
    }
    notifyListeners();
  }

  void _updateUI(DnsConfiguration cfg) {
    systemIsDoh = cfg.primaryDns == "127.0.0.1" ||
        cfg.dohUrl.isNotEmpty ||
        cfg.dotHostname.isNotEmpty;
    systemPrimary = systemIsDoh
        ? (cfg.dohUrl.isNotEmpty ? cfg.dohUrl : cfg.dotHostname)
        : (cfg.primaryDns.isEmpty ? "AUTO" : cfg.primaryDns);
    smartDnsValues = [systemPrimary.replaceFirst("https://", "")];

    smartProviderName = "CUSTOM RESOLVER";
    for (var p in _profiles) {
      if ((systemIsDoh &&
              (p.dohUrl == systemPrimary || p.dotHostname == systemPrimary)) ||
          (!systemIsDoh && p.primaryDns == systemPrimary)) {
        smartProviderName = p.name.toUpperCase();
        break;
      }
    }
  }

  Future<void> connectDns(
      DnsConfiguration config, SettingsProvider settings) async {
    ToastService().showToast("APPLYING...");
    final res = await _engine.connect(config, readableAdapterName);

    if (isDesktop) {
      if (res.success) {
        if (settings.autoFlush) await flushDns();
        if (settings.verifyConnection) {
          ToastService().showToast("VERIFYING...");
          bool works = await SystemUtils.verifyDnsResolution();
          ToastService()
              .showToast(works ? "CONNECTED & VERIFIED" : "DNS NO RESOLUTION");
        } else {
          ToastService().showToast("SUCCESS");
        }
      } else {
        ToastService().showToast("FAILED: ${res.message}");
      }
    } else {
      if (res.success) {
        _activeMobileConfig = config;
        _updateUI(config);
      }
      ToastService().showToast(res.message);
    }
    await refreshStatus();
  }

  void resetToDefaults() async {
    ToastService().showToast("RESETTING...");
    bool success = await _engine.disconnect(readableAdapterName);
    if (success) {
      if (!isDesktop) {
        _activeMobileConfig = null;
        systemPrimary = "AUTO";
        smartDnsValues = ["AUTO"];
        smartProviderName = "DISCONNECTED";
        ToastService().showToast("VPN DISCONNECTED");
      } else {
        ToastService().showToast("DHCP RESTORED");
      }
      refreshStatus();
    }
  }

  Future<void> flushDns() async {
    if (isDesktop) {
      await _engine.flush();
    } else if (_activeMobileConfig != null) {
      await _engine.disconnect("");
      await _engine.connect(_activeMobileConfig!, "");
      ToastService().showToast("VPN RESTARTED (CACHE FLUSHED)");
    }
  }

  Future<void> restartService() async {
    if (isDesktop) {
      ToastService().showToast("UAC PROMPT...");
      await SystemUtils.restartService();
    }
  }

  void smartImport(DnsConfiguration? suggested) {
    if (suggested == null) {
      ToastService().showToast("NO DATA FOUND");
      return;
    }
    addOrUpdateProfile(suggested);
    ToastService().showToast("IMPORTED");
  }

  DnsConfiguration getSystemAsConfig() => DnsConfiguration(
        name: "Live Backup",
        primaryDns: systemIsDoh ? "" : systemPrimary,
        dohUrl: systemIsDoh ? systemPrimary : "",
      );

  Future<void> refreshLatencies() async {
    final futures = _profiles.map((p) async {
      p.latencyMs = await SystemUtils.checkLatency(p.primaryDns);
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
    ToastService().showToast("COPIED");
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
    if (o < n) n -= 1;
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
