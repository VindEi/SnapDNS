import 'dart:io';
import 'dart:async';
import 'package:window_manager/window_manager.dart';

class SingleInstance {
  // ignore: unused_field
  static ServerSocket? _unixSocket;

  static Future<bool> ensureSingleInstance() async {
    if (Platform.isWindows) {
      // On Windows, the single-instance check is handled natively inside main.cpp
      // before any window or Dart VM is created to prevent "flashbang" window flashes.
      return true;
    } else if (Platform.isLinux || Platform.isMacOS) {
      return await _ensureUnix();
    }
    return true;
  }

  // --- UNIX DOMAIN SOCKET CHECK (macOS / Linux) ---
  static Future<bool> _ensureUnix() async {
    const socketPath = '/tmp/snapdns_single_instance.sock';
    try {
      // 1. Try binding to the socket path
      return await _bindUnix(socketPath);
    } catch (e) {
      // 2. Bind failed, check if the other instance is actually alive by connecting to it
      try {
        final client = await Socket.connect(
          InternetAddress(socketPath, type: InternetAddressType.unix),
          0,
          timeout: const Duration(seconds: 1),
        );
        client.add('show'.codeUnits);
        await client.flush();
        await client.close();
        return false; // Exit this duplicate process since the other instance is running
      } catch (_) {
        // 3. Connection failed, meaning the socket file is stale and dead!
        // Safely delete the orphaned file and attempt to bind again to let the app open.
        try {
          final file = File(socketPath);
          if (await file.exists()) {
            await file.delete();
          }
          return await _bindUnix(socketPath); // Try binding a clean socket
        } catch (_) {
          return true; // Extreme fallback: open app anyway if filesystem is locked
        }
      }
    }
  }

  static Future<bool> _bindUnix(String socketPath) async {
    final socket = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    _unixSocket = socket;

    socket.listen((client) {
      client.listen(
        (data) {
          final message = String.fromCharCodes(data).trim();
          if (message == 'show') {
            Future.microtask(() async {
              try {
                await windowManager.show();
                await windowManager.focus();
              } catch (_) {}
            });
          }
        },
        onDone: () => client.close(),
        onError: (_) => client.destroy(),
      );
    });
    return true;
  }
}
