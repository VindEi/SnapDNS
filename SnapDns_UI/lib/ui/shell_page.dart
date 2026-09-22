import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../providers/settings_provider.dart';
import '../services/update_service.dart';
import '../providers/toast_provider.dart';
import '../services/tray_manager.dart';
import 'pages/main_page.dart';
import 'pages/profiles_page.dart';
import 'pages/settings_page.dart';
import 'widgets/common/title_bar.dart';
import 'widgets/common/toast_overlay.dart';
import 'widgets/common/update_dialog.dart';

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});
  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> with WindowListener {
  static const List<Widget> _pages = [
    SettingsPage(),
    MainPage(),
    ProfilesPage()
  ];

  bool isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    if (isDesktop) {
      windowManager.addListener(this);
    }

    Future.delayed(
        const Duration(seconds: 3), () => _checkForUpdates(silent: true));

    if (isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<SettingsProvider>().refreshSystemIcons();
      });
    }
  }

  void _checkForUpdates({bool silent = false}) async {
    final update = await UpdateService.checkUpdate();

    if (!mounted) return;

    if (update != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => UpdateDialog(info: update),
      );
    } else if (!silent) {
      context.read<ToastProvider>().showToast("YOU ARE UP TO DATE");
    }
  }

  @override
  void dispose() {
    if (isDesktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowClose() {
    context.read<SettingsProvider>().handleWindowClose();
  }

  @override
  void onWindowFocus() {
    if (isDesktop) {
      try {
        AppTrayManager().hideTray();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex =
        context.select<SettingsProvider, int>((p) => p.currentPageIndex);
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    final bool isWide = MediaQuery.of(context).size.width >= 600 ||
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        top: !isDesktop,
        child: Column(
          children: [
            const CustomTitleBar(),
            Expanded(
              child: Row(
                children: [
                  if (isWide)
                    Container(
                      width: 50,
                      decoration: BoxDecoration(
                        color: theme.scaffoldBackgroundColor,
                        border: Border(
                          right: BorderSide(
                            color: theme.colorScheme.outline
                                .withValues(alpha: 0.1),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _navBtn(Icons.settings_outlined, 0, selectedIndex,
                              accent, theme.colorScheme),
                          const SizedBox(height: 30),
                          _navBtn(Icons.bolt_rounded, 1, selectedIndex, accent,
                              theme.colorScheme),
                          const SizedBox(height: 30),
                          _navBtn(Icons.dns_outlined, 2, selectedIndex, accent,
                              theme.colorScheme),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Stack(
                      children: [
                        IndexedStack(index: selectedIndex, children: _pages),
                        const ToastOverlay(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!isWide)
              Container(
                padding: EdgeInsets.only(
                    bottom:
                        isDesktop ? 0 : MediaQuery.of(context).padding.bottom),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  border: Border(
                    top: BorderSide(
                        color: theme.colorScheme.outline.withValues(alpha: 0.1),
                        width: 0.5),
                  ),
                ),
                child: SizedBox(
                  height: 50,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _navBtn(Icons.settings_outlined, 0, selectedIndex, accent,
                          theme.colorScheme),
                      const SizedBox(width: 50),
                      _navBtn(Icons.bolt_rounded, 1, selectedIndex, accent,
                          theme.colorScheme),
                      const SizedBox(width: 50),
                      _navBtn(Icons.dns_outlined, 2, selectedIndex, accent,
                          theme.colorScheme),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _navBtn(
      IconData icon, int index, int current, Color accent, ColorScheme cs) {
    bool active = current == index;
    return GestureDetector(
      onTap: () => context.read<SettingsProvider>().setPage(index),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: 60,
          height: 50,
          child: Icon(icon,
              color: active ? accent : cs.onSurface.withValues(alpha: 0.2),
              size: 20),
        ),
      ),
    );
  }
}
