import 'dart:io';
import 'dart:ffi';
import 'package:ffi/ffi.dart';

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _user32 = DynamicLibrary.open('user32.dll');

final _createMutexW = _kernel32.lookupFunction<
    Pointer<Void> Function(Pointer<Void>, Int32, Pointer<Utf16>),
    Pointer<Void> Function(Pointer<Void>, int, Pointer<Utf16>)>('CreateMutexW');

final _getLastError =
    _kernel32.lookupFunction<Uint32 Function(), int Function()>('GetLastError');

// FIX: Added direct kernel32 binding to CloseHandle
final _closeHandle = _kernel32.lookupFunction<Int32 Function(Pointer<Void>),
    int Function(Pointer<Void>)>('CloseHandle');

final _findWindowW = _user32.lookupFunction<
    Pointer<Void> Function(Pointer<Utf16>, Pointer<Utf16>),
    Pointer<Void> Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');

final _showWindow = _user32.lookupFunction<Int32 Function(Pointer<Void>, Int32),
    int Function(Pointer<Void>, int)>('ShowWindow');

final _setForegroundWindow = _user32.lookupFunction<
    Int32 Function(Pointer<Void>),
    int Function(Pointer<Void>)>('SetForegroundWindow');

class SingleInstance {
  // Global Mutex reference to persist across IDE Hot Restarts
  static Pointer<Void>? _mutexHandle;

  static bool ensureSingleInstance() {
    if (!Platform.isWindows) return true;

    // Bypasses check if the current process space is already holding a valid Mutex handle
    if (_mutexHandle != null && _mutexHandle!.address != 0) {
      return true;
    }

    return using((Arena arena) {
      final mutexName =
          'SnapDns_SingleInstance_Mutex_v2'.toNativeUtf16(allocator: arena);
      final handle = _createMutexW(nullptr, 0, mutexName);

      // 183 = ERROR_ALREADY_EXISTS
      if (_getLastError() == 183) {
        if (handle.address != 0 && handle.address != -1) {
          _closeHandle(handle); // Safely release duplicate handle resources
        }

        final windowName1 = 'SnapDns'.toNativeUtf16(allocator: arena);
        final windowName2 = 'SnapDns '.toNativeUtf16(allocator: arena);

        var hwnd = _findWindowW(nullptr, windowName1);
        if (hwnd.address == 0) hwnd = _findWindowW(nullptr, windowName2);

        if (hwnd.address != 0) {
          _showWindow(hwnd, 9); // 9 = SW_RESTORE
          _setForegroundWindow(hwnd);
        }

        return false;
      }

      _mutexHandle = handle;
      return true;
    });
  }
}
