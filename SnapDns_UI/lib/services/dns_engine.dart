import 'dart:io';
import '../models/dns_configuration.dart';
import '../models/pipe_models.dart';
import 'ipc_client.dart';
import 'mobile_vpn_engine.dart';

class DnsEngineState {
  final bool isServiceConnected;
  final bool isMobileConnected;
  final List<String> adapters;
  final String? preferredAdapter;
  final DnsConfiguration? configuration;

  DnsEngineState({
    this.isServiceConnected = false,
    this.isMobileConnected = false,
    this.adapters = const [],
    this.preferredAdapter,
    this.configuration,
  });
}

abstract class DnsEngine {
  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static DnsEngine create() {
    return isDesktop ? DesktopDnsEngine() : MobileDnsEngine();
  }

  Future<void> initialize();
  Future<PipeResponse> connect(DnsConfiguration config, String adapterName);
  Future<bool> disconnect(String adapterName);
  Future<void> flush();
  Future<DnsEngineState> getStatus(String adapterName);
}

class DesktopDnsEngine implements DnsEngine {
  final IpcClient _ipc = IpcClient();

  @override
  Future<void> initialize() async {}

  @override
  Future<PipeResponse> connect(
      DnsConfiguration config, String adapterName) async {
    return await _ipc.sendCommand(PipeRequest(
      command: PipeCommandType.applyDns,
      configuration: config,
      adapterName: adapterName,
    ));
  }

  @override
  Future<bool> disconnect(String adapterName) async {
    final res = await _ipc.sendCommand(PipeRequest(
      command: PipeCommandType.resetDhcp,
      adapterName: adapterName,
    ));
    return res.success;
  }

  @override
  Future<void> flush() async {
    await _ipc.sendCommand(PipeRequest(command: PipeCommandType.flushDns));
  }

  @override
  Future<DnsEngineState> getStatus(String adapterName) async {
    final res = await _ipc.sendCommand(PipeRequest(
      command: PipeCommandType.getSyncState,
      adapterName: adapterName,
    ));
    if (!res.success) return DnsEngineState(isServiceConnected: false);
    return DnsEngineState(
      isServiceConnected: true,
      adapters: res.adapters ?? [],
      preferredAdapter: res.preferredAdapterName,
      configuration: res.configuration,
    );
  }
}

class MobileDnsEngine implements DnsEngine {
  @override
  Future<void> initialize() async {}

  @override
  Future<PipeResponse> connect(
      DnsConfiguration config, String adapterName) async {
    bool success = await MobileVpnEngine.startDnsTunnel(config);
    return PipeResponse(
        success: success,
        message: success ? "VPN TUNNEL ACTIVE" : "VPN DENIED/FAILED");
  }

  @override
  Future<bool> disconnect(String adapterName) async {
    await MobileVpnEngine.stopTunnel();
    return true;
  }

  @override
  Future<void> flush() async {}

  @override
  Future<DnsEngineState> getStatus(String adapterName) async {
    bool isConnected = await MobileVpnEngine.isConnected();
    return DnsEngineState(
      isServiceConnected: true,
      isMobileConnected: isConnected,
    );
  }
}
