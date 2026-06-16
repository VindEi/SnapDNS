import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'core/theme.dart';
import 'core/constants.dart';
import 'services/tray_manager.dart';
import 'services/mobile_vpn_engine.dart';
import 'providers/toast_provider.dart';
import 'services/single_instance.dart';
import 'providers/dns_provider.dart';
import 'providers/dns_input_provider.dart';
import 'providers/settings_provider.dart';
import 'ui/shell_page.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Enforce Single Instance on Windows immediately
  if (!SingleInstance.ensureSingleInstance()) {
    exit(0);
  }

  await AppConstants.initPaths();

  final settingsProvider = SettingsProvider();
  await settingsProvider.initialize();

  final toastProvider = ToastProvider();

  bool isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  if (isDesktop) {
    await windowManager.ensureInitialized();
    bool startMinimized = args.contains('--minimized');
    await windowManager.setPreventClose(true);

    final tray = AppTrayManager();

    // FIX: Pass the flush-and-exit callback directly to the tray manager
    await tray.initialize(onExit: () async {
      await settingsProvider.flushSettings();
      try {
        await AppTrayManager()
            .hideTray()
            .timeout(const Duration(milliseconds: 200));
      } catch (_) {}
      exit(0);
    });

    WindowOptions windowOptions = const WindowOptions(
      size: Size(400, 600),
      minimumSize: Size(400, 600),
      maximumSize: Size(400, 600),
      center: true,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (startMinimized) {
        await tray.showTray();
      } else {
        await windowManager.show();
      }
      await windowManager.setResizable(false);
    });
  } else if (Platform.isAndroid) {
    try {
      await MobileVpnEngine.initialize();
    } catch (e) {
      debugPrint("Mobile VPN Failed: $e");
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: toastProvider),
        ChangeNotifierProvider(create: (_) => DnsInputProvider()),
        ChangeNotifierProvider(
            create: (_) => DnsProvider(toastProvider)..initialize()),
      ],
      child: const SnapDnsApp(),
    ),
  );
}

class SnapDnsApp extends StatelessWidget {
  const SnapDnsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<SettingsProvider, (bool, Color)>(
      selector: (_, p) => (p.isDarkMode, p.accentColor),
      builder: (context, data, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: "SnapDns",
          themeMode: data.$1 ? ThemeMode.dark : ThemeMode.light,
          theme: SnapDnsTheme.createTheme(Brightness.light, data.$2),
          darkTheme: SnapDnsTheme.createTheme(Brightness.dark, data.$2),
          home: const ShellPage(),
        );
      },
    );
  }
}
