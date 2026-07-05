import 'dart:io';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/foundation.dart';

class AppTrayManager {
  static final AppTrayManager _instance = AppTrayManager._internal();
  factory AppTrayManager() => _instance;
  AppTrayManager._internal();

  SystemTray? _systemTray;
  Menu? _menu;
  String? _trayIconPath;
  bool _isActive = false;
  VoidCallback? _onExit;
  String? _currentTooltip; 

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> initialize({VoidCallback? onExit}) async {
    if (_isDesktop) {
      _systemTray = SystemTray();
      _menu = Menu();
      _onExit = onExit;
    }
  }

  void setTrayPath(String path) {
    if (!_isDesktop) return;
    _trayIconPath = path;
    if (_isActive) _applyTrayImage();
  }

  Future<void> updateTooltip(String text) async {
    if (!_isDesktop) return;
    _currentTooltip = text;
    if (_systemTray != null && _isActive) {
      try {
        await _systemTray!.setToolTip(text);
      } catch (_) {}
    }
  }

  Future<void> _applyTrayImage() async {
    if (_trayIconPath == null || _systemTray == null) return;
    try {
      if (File(_trayIconPath!).existsSync()) {
        await _systemTray!.setImage(_trayIconPath!);
      }
    } catch (_) {}
  }

  Future<void> showTray() async {
    if (!_isDesktop || _isActive || _systemTray == null || _menu == null) {
      return;
    }

    try {
      final String fallbackAsset =
          Platform.isWindows ? 'assets/SnapDns.ico' : 'assets/SnapDns.png';

      final String initialPath =
          (_trayIconPath != null && File(_trayIconPath!).existsSync())
              ? _trayIconPath!
              : fallbackAsset;

      final String initialTooltip = _currentTooltip ?? "SnapDNS";

      await _systemTray!.initSystemTray(
        title: initialTooltip,
        iconPath: initialPath,
      );

      // Force-set the hover tooltip on creation
      await _systemTray!.setToolTip(initialTooltip);

      if (initialPath != _trayIconPath && _trayIconPath != null) {
        await _applyTrayImage();
      }

      await _menu!.buildFrom([
        MenuItemLabel(label: 'Show', onClicked: (_) => _restore()),
        MenuItemLabel(
            label: 'Exit',
            onClicked: (_) => _onExit != null ? _onExit!() : exit(0)),
      ]);

      await _systemTray!.setContextMenu(_menu!);

      _systemTray!.registerSystemTrayEventHandler((eventName) {
        if (eventName == kSystemTrayEventClick) {
          _restore();
        } else if (eventName == kSystemTrayEventRightClick) {
          _systemTray!.popUpContextMenu();
        }
      });

      _isActive = true;
    } catch (e) {
      debugPrint("DEBUG: [Tray] showTray critical failure: $e");
    }
  }

  Future<void> hideTray() async {
    if (!_isDesktop || !_isActive || _systemTray == null) return;
    try {
      _isActive = false;
      await _systemTray!.destroy();
    } catch (_) {}
  }

  void _restore() {
    if (!_isDesktop) return;

    Future.microtask(() async {
      try {
        await windowManager.show();
        await windowManager.focus();
        await hideTray();
      } catch (_) {}
    });
  }
}
