import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import '../models/app_settings.dart';
import '../core/constants.dart';
import '../utils/icon_engine.dart';
import '../services/tray_manager.dart';
import '../services/startup_utils.dart';

extension HexColor on Color {
  static Color fromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    try {
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return const Color(0xFF00C8C8);
    }
  }

  String toHex() =>
      '#${toARGB32().toRadixString(16).substring(2).toUpperCase()}';
}

class SettingsProvider extends ChangeNotifier {
  AppSettings _settings = AppSettings();
  Timer? _confirmTimer;
  Timer? _saveDebounce;
  int currentPageIndex = 1;
  bool isResetConfirming = false;
  String resetButtonText = "RESET DNS PROFILES";
  String? _cachedSvgTemplate;

  bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  bool get runOnStartup => _settings.runOnStartup;
  bool get minimizeToTray => _settings.minimizeToTray;
  bool get showNotifications => _settings.showNotifications;
  bool get autoFlush => _settings.autoFlush;
  bool get launchHidden => _settings.launchHidden;
  bool get verifyConnection => _settings.verifyConnection;
  bool get isDarkMode => _settings.theme == "Dark";
  Color get accentColor => HexColor.fromHex(_settings.accentColor);
  String get versionText => "SnapDns v${AppConstants.appVersion}";

  Future<void> initialize() async {
    await loadSettings();
    if (isDesktop && _settings.runOnStartup) {
      await StartupUtils.toggle(true, launchHidden: _settings.launchHidden);
    }
    if (isDesktop) {
      Future.delayed(
          const Duration(milliseconds: 1000), () => _refreshSystemIcons());
    }
  }

  void setPage(int index) {
    currentPageIndex = index;
    notifyListeners();
  }

  void toggleRunOnStartup(bool v) async {
    if (!isDesktop) return;
    _settings.runOnStartup = v;
    _save();
    await StartupUtils.toggle(v, launchHidden: _settings.launchHidden);
    notifyListeners();
  }

  void toggleTray(bool v) {
    _settings.minimizeToTray = v;
    _save();
    notifyListeners();
  }

  void toggleNotifications(bool v) {
    _settings.showNotifications = v;
    _save();
    notifyListeners();
  }

  void toggleAutoFlush(bool v) {
    _settings.autoFlush = v;
    _save();
    notifyListeners();
  }

  void toggleLaunchHidden(bool v) async {
    if (!isDesktop) return;
    _settings.launchHidden = v;
    _save();
    if (_settings.runOnStartup) {
      await StartupUtils.toggle(true, launchHidden: v);
    }
    notifyListeners();
  }

  void toggleVerify(bool v) {
    _settings.verifyConnection = v;
    _save();
    notifyListeners();
  }

  void toggleTheme() async {
    _settings.theme = isDarkMode ? "Light" : "Dark";
    _save();
    notifyListeners();
    if (isDesktop) await _refreshSystemIcons();
  }

  void updateAccentColor(Color color) async {
    _settings.accentColor = color.toHex();
    _save();
    notifyListeners();
    if (isDesktop) await _refreshSystemIcons();
  }

  void updateAccentHex(String hex) async {
    if (RegExp(r'^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').hasMatch(hex)) {
      _settings.accentColor = hex.startsWith('#') ? hex : '#$hex';
      _save();
      notifyListeners();
      if (isDesktop) await _refreshSystemIcons();
    }
  }

  Future<void> _refreshSystemIcons() async {
    if (!isDesktop) return;
    try {
      _cachedSvgTemplate ??=
          await rootBundle.loadString('assets/SnapDns.svg', cache: false);
      final paths = await IconEngine.generateSystemIcons(
          rawSvg: _cachedSvgTemplate!,
          accentColor: accentColor,
          isDark: isDarkMode);
      if (paths != null) {
        await Future.delayed(const Duration(milliseconds: 150));
        await windowManager.setIcon(paths['taskbar']!);
        if (Platform.isWindows) {
          await windowManager.setTitle("SnapDns ");
          await Future.delayed(const Duration(milliseconds: 50));
          await windowManager.setTitle("SnapDns");
        }
        AppTrayManager().setTrayPath(paths['tray']!);
      }
    } catch (e) {
      debugPrint("DEBUG: [IconSystem] Refresh Error: $e");
    }
  }

  Future<void> handleWindowClose() async {
    if (!isDesktop) return;
    if (_settings.minimizeToTray) {
      windowManager.hide();
      Future.microtask(() => AppTrayManager().showTray());
    } else {
      // FIX: Destroy tray explicitly to prevent ghost icons on Windows
      await AppTrayManager().hideTray();
      await windowManager.destroy();
    }
  }

  void resetProviders(VoidCallback onReset) {
    if (!isResetConfirming) {
      isResetConfirming = true;
      resetButtonText = "CONFIRM RESET?";
      notifyListeners();
      _confirmTimer?.cancel();
      _confirmTimer = Timer(const Duration(seconds: 3), () {
        if (hasListeners) {
          isResetConfirming = false;
          resetButtonText = "RESET DNS PROFILES";
          notifyListeners();
        }
      });
      return;
    }
    onReset();
    isResetConfirming = false;
    resetButtonText = "RESET DNS PROFILES";
    notifyListeners();
  }

  void openLeakTest() => launchUrl(Uri.parse("https://dnsleaktest.com"),
      mode: LaunchMode.externalApplication);

  void _save() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final json = jsonEncode(_settings.toJson());
        final file = File(AppConstants.settingsFilePath);
        final tempFile = File('${AppConstants.settingsFilePath}.tmp');

        // FIX: Atomic save
        await tempFile.writeAsString(json, flush: true);
        if (await file.exists()) {
          await file.delete();
        }
        await tempFile.rename(file.path);
      } catch (_) {}
    });
  }

  Future<void> loadSettings() async {
    try {
      final file = File(AppConstants.settingsFilePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          _settings = AppSettings.fromJson(jsonDecode(content));
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _confirmTimer?.cancel();
    _saveDebounce?.cancel();
    super.dispose();
  }

  Future<void> exportProfiles(String json) async {
    String? path = await FilePicker.saveFile(
        fileName: 'profiles.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: utf8.encode(json));
    if (path != null) await File(path).writeAsString(json);
  }

  Future<void> importProfiles(Function(String) onData) async {
    FilePickerResult? res = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['json']);
    if (res != null && res.files.single.path != null) {
      final content = await File(res.files.single.path!).readAsString();
      if (content.trim().isNotEmpty) onData(content);
    }
  }
}
