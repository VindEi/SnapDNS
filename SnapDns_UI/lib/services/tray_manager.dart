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
  VoidCallback? _onExit; // FIX: Cached exit callback

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  // FIX: Accept a custom onExit callback during initialization
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

      await _systemTray!.initSystemTray(
        title: "SnapDns",
        iconPath: initialPath,
      );

      if (initialPath != _trayIconPath && _trayIconPath != null) {
        await _applyTrayImage();
      }

      await _menu!.buildFrom([
        MenuItemLabel(label: 'Show', onClicked: (_) => _restore()),
        MenuItemLabel(
            label: 'Exit',
            onClicked: (_) {
              // FIX: Execute custom exit routine to flush configurations to disk before termination
              if (_onExit != null) {
                _onExit!();
              } else {
                exit(0);
              }
            }),
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
