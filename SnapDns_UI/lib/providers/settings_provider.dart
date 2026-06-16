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
  // FIX: Overhauled hex parser to support CSS shorthand formats (3 & 4 chars)
  // and protect the alpha channel from being cleared to transparent (zero-alpha).
  static Color fromHex(String hexString) {
    String hex = hexString.replaceFirst('#', '').trim();

    // Handle 3-character shorthand (e.g. "FFF" -> "FFFFFF")
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    // Handle 4-character shorthand (e.g. "FFFF" -> "FFFFFFFF")
    else if (hex.length == 4) {
      hex = hex.split('').map((c) => '$c$c').join();
    }

    // Default to fully opaque if no alpha is provided
    if (hex.length == 6) {
      hex = 'ff$hex';
    }

    try {
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return const Color(0xFF00C8C8); // Fallback to default Cyan
    }
  }

  String toHex() =>
      '#${toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  Color get contrastColor =>
      computeLuminance() > 0.4 ? Colors.black : Colors.white;
}

class SettingsProvider extends ChangeNotifier {
  AppSettings _settings = AppSettings();
  Timer? _confirmTimer;
  Timer? _saveDebounce;
  Timer? _iconDebounce;
  int currentPageIndex = 1;
  bool isResetConfirming = false;
  String resetButtonText = "RESET DNS PROFILES";
  String? _cachedSvgTemplate;

  static const List<String> accentPresets = [
    "#00C8C8",
    "#FF9500",
    "#AF52DE",
    "#FF2D55"
  ];

  String _customHexPreview = "#00C8C8";
  String get customHexPreview => _customHexPreview;

  bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  bool get runOnStartup => _settings.runOnStartup;
  bool get minimizeToTray => _settings.minimizeToTray;
  bool get showNotifications => _settings.showNotifications;
  bool get autoFlush => _settings.autoFlush;
  bool get launchHidden => _settings.launchHidden;
  bool get verifyConnection => _settings.verifyConnection;
  bool get isDarkMode => _settings.theme == "Dark";

  bool get isAdaptive => _settings.accentColor == "adaptive";

  bool get isCustomColor {
    if (isAdaptive) {
      return false;
    }
    return !accentPresets.contains(accentColor.toHex());
  }

  Color get accentColor {
    if (isAdaptive) {
      return isDarkMode ? Colors.white : Colors.black;
    }
    return HexColor.fromHex(_settings.accentColor);
  }

  String get versionText => "SnapDns v${AppConstants.appVersion}";

  Future<void> initialize() async {
    await loadSettings();
    _customHexPreview = isAdaptive ? "#00C8C8" : _settings.accentColor;
    if (isDesktop && _settings.runOnStartup) {
      try {
        await StartupUtils.toggle(true, launchHidden: _settings.launchHidden);
      } catch (_) {}
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

    try {
      await StartupUtils.toggle(v, launchHidden: _settings.launchHidden);
    } catch (e) {
      debugPrint("DEBUG: [Startup] Toggle run-on-startup failed: $e");
      _settings.runOnStartup = !v;
      _save();
    }
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
      try {
        await StartupUtils.toggle(true, launchHidden: v);
      } catch (e) {
        debugPrint("DEBUG: [Startup] Toggle launch-hidden failed: $e");
        _settings.launchHidden = !v;
        _save();
      }
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
    if (isDesktop) {
      await refreshSystemIcons();
    }
  }

  void updateAccentColor(Color color) async {
    final hex = color.toHex();
    _settings.accentColor = hex;
    _customHexPreview = hex;
    _save();
    notifyListeners();
    if (isDesktop) {
      await refreshSystemIcons();
    }
  }

  void setAdaptiveAccent() async {
    _settings.accentColor = "adaptive";
    _save();
    notifyListeners();
    if (isDesktop) {
      await refreshSystemIcons();
    }
  }

  void applyCustomHex() async {
    _settings.accentColor = _customHexPreview;
    _save();
    notifyListeners();
    if (isDesktop) {
      await refreshSystemIcons();
    }
  }

  void updateCustomHexPreview(String hex) {
    _customHexPreview = hex;
    if (RegExp(r'^#?([0-9a-fA-F]{6})$').hasMatch(hex)) {
      final parsed = hex.startsWith('#') ? hex : '#$hex';
      _customHexPreview = parsed;
      _settings.accentColor = parsed;
      _save();

      if (isDesktop) {
        _iconDebounce?.cancel();
        _iconDebounce = Timer(const Duration(milliseconds: 400), () {
          refreshSystemIcons();
        });
      }
    }
    notifyListeners();
  }

  Future<void> refreshSystemIcons() async {
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
      await flushSettings();

      try {
        await AppTrayManager()
            .hideTray()
            .timeout(const Duration(milliseconds: 200));
      } catch (_) {}
      exit(0);
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
    _saveDebounce = Timer(const Duration(milliseconds: 500), _saveNow);
  }

  Future<void> _saveNow() async {
    try {
      final json = jsonEncode(_settings.toJson());
      final file = File(AppConstants.settingsFilePath);
      final tempFile = File('${AppConstants.settingsFilePath}.tmp');

      await tempFile.writeAsString(json, flush: true);
      if (await file.exists()) {
        await file.delete();
      }
      await tempFile.rename(file.path);
    } catch (_) {}
  }

  Future<void> flushSettings() async {
    if (_saveDebounce?.isActive ?? false) {
      _saveDebounce?.cancel();
      await _saveNow();
    }
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
    _iconDebounce?.cancel();
    super.dispose();
  }

  Future<void> exportProfiles(String json) async {
    String? path = await FilePicker.saveFile(
        fileName: 'profiles.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: utf8.encode(json));
    if (path != null) {
      await File(path).writeAsString(json);
    }
  }

  Future<void> importProfiles(Function(String) onData) async {
    FilePickerResult? res = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['json']);
    if (res != null && res.files.single.path != null) {
      final content = await File(res.files.single.path!).readAsString();
      if (content.trim().isNotEmpty) {
        onData(content);
      }
    }
  }
}
