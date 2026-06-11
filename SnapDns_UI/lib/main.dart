import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'core/theme.dart';
import 'services/tray_manager.dart';
import 'core/constants.dart';
import 'services/mobile_vpn_engine.dart';
import 'services/toast_service.dart';
import 'providers/dns_provider.dart';
import 'providers/dns_input_provider.dart';
import 'providers/settings_provider.dart';
import 'ui/shell_page.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConstants.initPaths();

  final settingsProvider = SettingsProvider();
  await settingsProvider.initialize();

  bool isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  if (isDesktop) {
    await windowManager.ensureInitialized();
    bool startMinimized = args.contains('--minimized');
    await windowManager.setPreventClose(true);

    final tray = AppTrayManager();
    await tray.initialize();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(400, 600),
      minimumSize: Size(400, 600),
      maximumSize: Size(400, 600),
      center: true,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      // FIXED: Added curly braces for the strict linter
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
        ChangeNotifierProvider(create: (_) => ToastService()),
        ChangeNotifierProvider(create: (_) => DnsInputProvider()),
        ChangeNotifierProvider(create: (_) => DnsProvider()..initialize()),
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
