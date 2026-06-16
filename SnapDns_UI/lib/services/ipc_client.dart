import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import '../models/pipe_models.dart';
import '../core/constants.dart';

final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _createFileW = _kernel32.lookupFunction<
    Pointer<Void> Function(Pointer<Utf16>, Uint32, Uint32, Pointer<Void>,
        Uint32, Uint32, Pointer<Void>),
    Pointer<Void> Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int,
        Pointer<Void>)>('CreateFileW');

final _writeFile = _kernel32.lookupFunction<
    Int32 Function(
        Pointer<Void>, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Void>),
    int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint32>,
        Pointer<Void>)>('WriteFile');

final _readFile = _kernel32.lookupFunction<
    Int32 Function(
        Pointer<Void>, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Void>),
    int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint32>,
        Pointer<Void>)>('ReadFile');

final _closeHandle = _kernel32.lookupFunction<Int32 Function(Pointer<Void>),
    int Function(Pointer<Void>)>('CloseHandle');

const int genericRead = 0x80000000;
const int genericWrite = 0x40000000;
const int openExisting = 3;
final Pointer<Void> invalidHandleValue = Pointer<Void>.fromAddress(-1);

class IpcClient {
  static final _SimpleMutex _lock = _SimpleMutex();

  Future<PipeResponse> sendCommand(PipeRequest request) async {
    return await _lock.protect(() async {
      if (Platform.isWindows) {
        return await Isolate.run(() => _transferWindows(request));
      } else {
        return await _transferUnix(request);
      }
    });
  }

  static PipeResponse _transferWindows(PipeRequest request) {
    return using((Arena arena) {
      final pName = AppConstants.pipeName.toNativeUtf16(allocator: arena);
      Pointer<Void> hPipe = invalidHandleValue;

      try {
        for (int i = 0; i < 3; i++) {
          hPipe = _createFileW(pName, genericRead | genericWrite, 0, nullptr,
              openExisting, 0, nullptr);
          if (hPipe.address != invalidHandleValue.address) break;
          sleep(const Duration(milliseconds: 100));
        }

        if (hPipe.address == invalidHandleValue.address) {
          return PipeResponse(success: false, message: "Offline");
        }

        final payload = utf8.encode(jsonEncode(request.toJson()));
        final writeData = Uint8List(4 + payload.length);
        ByteData.view(writeData.buffer)
            .setInt32(0, payload.length, Endian.little);
        writeData.setAll(4, payload);

        Pointer<Uint8> pWriteBuf = arena<Uint8>(writeData.length);
        pWriteBuf.asTypedList(writeData.length).setAll(0, writeData);
        Pointer<Uint32> dwWritten = arena<Uint32>();
        Pointer<Uint8> pHeaderBuf = arena<Uint8>(4);
        Pointer<Uint32> dwRead = arena<Uint32>();

        if (_writeFile(
                hPipe, pWriteBuf, writeData.length, dwWritten, nullptr) ==
            0) {
          throw "Pipe Write Error";
        }
        if (_readFile(hPipe, pHeaderBuf, 4, dwRead, nullptr) == 0) {
          throw "Pipe Header Error";
        }

        final resLen = ByteData.view(pHeaderBuf.asTypedList(4).buffer)
            .getInt32(0, Endian.little);
        if (resLen <= 0 || resLen > 1024 * 1024) throw "Invalid Payload Size";

        Pointer<Uint8> pResBuf = arena<Uint8>(resLen);
        if (_readFile(hPipe, pResBuf, resLen, dwRead, nullptr) == 0) {
          throw "Pipe Body Error";
        }

        final rawString = utf8.decode(pResBuf.asTypedList(resLen));
        return PipeResponse.fromJson(jsonDecode(rawString));
      } catch (e) {
        debugPrint("IPC Windows Error: $e");
        return PipeResponse(success: false, message: "Comm Error");
      } finally {
        if (hPipe.address != invalidHandleValue.address) _closeHandle(hPipe);
      }
    });
  }

  static Future<PipeResponse> _transferUnix(PipeRequest request) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
          InternetAddress(AppConstants.unixSocketPath,
              type: InternetAddressType.unix),
          0,
          timeout: const Duration(seconds: 1));
      final payload = utf8.encode(jsonEncode(request.toJson()));
      final header = ByteData(4)..setInt32(0, payload.length, Endian.little);

      socket.add(header.buffer.asUint8List());
      socket.add(payload);
      await socket.flush();

      final List<int> responseBytes = [];
      await for (var chunk in socket) {
        responseBytes.addAll(chunk);

        // FIX: Ultra-fast, allocation-free, and safe Little-Endian 32-bit length header parser.
        // Prevents redundant sublist creation during chunk streaming.
        if (responseBytes.length >= 4) {
          final int total = responseBytes[0] |
              (responseBytes[1] << 8) |
              (responseBytes[2] << 16) |
              (responseBytes[3] << 24) + 4;
          if (responseBytes.length >= total) break;
        }
      }

      // FIX: Guard check to prevent out-of-bounds RangeError on premature socket shutdowns
      if (responseBytes.length < 4) {
        return PipeResponse(success: false, message: "Offline");
      }

      return PipeResponse.fromJson(
          jsonDecode(utf8.decode(responseBytes.sublist(4))));
    } catch (e) {
      return PipeResponse(success: false, message: "Offline");
    } finally {
      await socket?.close();
    }
  }
}

class _SimpleMutex {
  Future<void> _last = Future.value();

  Future<T> protect<T>(Future<T> Function() action) {
    final completer = Completer<void>();
    final result = _last.then((_) => action()).whenComplete(() {
      completer.complete();
    });
    _last = completer.future;
    return result;
  }
}
