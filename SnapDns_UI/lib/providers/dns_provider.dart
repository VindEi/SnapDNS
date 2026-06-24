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
          smartProviderName = "DISCONNECTED";
        }
      }
      notifyListeners();
    } finally {
      _isRefreshing = false;
    }
  }

  void _updateUI(DnsConfiguration cfg) {
    systemIsDoh = cfg.primaryDns == "127.0.0.1" ||
        cfg.dohUrl.isNotEmpty ||
        cfg.dotHostname.isNotEmpty;

    systemPrimary = systemIsDoh
        ? (cfg.dohUrl.isNotEmpty ? cfg.dohUrl : cfg.dotHostname)
        : (cfg.primaryDns.isEmpty || cfg.primaryDns == "DHCP"
            ? "AUTO"
            : cfg.primaryDns);

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
    _toastProvider.showToast("APPLYING...");
    final res = await _engine.connect(config, readableAdapterName);

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
        smartProviderName = "DISCONNECTED";

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
        // FIX: Verify if the background flush command actually succeeded on the service daemon
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
