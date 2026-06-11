import 'dns_configuration.dart';

enum PipeCommandType {
  applyDns,
  resetDhcp,
  getConfiguration,
  getAdapters,
  getPreferredAdapter,
  flushDns,
  getSyncState, // Added
}

class PipeRequest {
  final PipeCommandType command;
  final String adapterName;
  final DnsConfiguration? configuration;

  PipeRequest({
    required this.command,
    this.adapterName = "",
    this.configuration,
  });

  Map<String, dynamic> toJson() => {
    'command': command.name,
    'adapterName': adapterName,
    'configuration': configuration?.toJson(),
  };
}

class PipeResponse {
  final bool success;
  final String message;
  final DnsConfiguration? configuration;
  final List<String>? adapters;
  final String? preferredAdapterName;

  PipeResponse({
    required this.success,
    this.message = "",
    this.configuration,
    this.adapters,
    this.preferredAdapterName,
  });

  factory PipeResponse.fromJson(Map<String, dynamic> json) => PipeResponse(
    success: json['success'] ?? false,
    message: json['message'] ?? "",
    configuration: json['configuration'] != null
        ? DnsConfiguration.fromJson(json['configuration'])
        : null,
    adapters: json['adapters'] != null
        ? List<String>.from(json['adapters'])
        : null,
    preferredAdapterName: json['preferredAdapterName'],
  );
}
