import 'package:uuid/uuid.dart';

class DnsConfiguration {
  final String id;
  String name;
  String primaryDns;
  String secondaryDns;
  String ipv6Primary;
  String ipv6Secondary;
  String dohUrl;
  String dotHostname;
  int latencyMs;

  DnsConfiguration({
    String? id,
    this.name = "",
    this.primaryDns = "",
    this.secondaryDns = "",
    this.ipv6Primary = "",
    this.ipv6Secondary = "",
    this.dohUrl = "",
    this.dotHostname = "",
    this.latencyMs = -1,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'primaryDns': primaryDns,
    'secondaryDns': secondaryDns,
    'ipv6Primary': ipv6Primary,
    'ipv6Secondary': ipv6Secondary,
    'dohUrl': dohUrl,
    'dotHostname': dotHostname,
  };

  factory DnsConfiguration.fromJson(Map<String, dynamic> json) {
    return DnsConfiguration(
      id: (json['id'] ?? const Uuid().v4()).toString(),
      name: (json['name'] ?? "Unnamed Profile").toString(),
      primaryDns: (json['primaryDns'] ?? "").toString(),
      secondaryDns: (json['secondaryDns'] ?? "").toString(),
      ipv6Primary: (json['ipv6Primary'] ?? "").toString(),
      ipv6Secondary: (json['ipv6Secondary'] ?? "").toString(),
      dohUrl: (json['dohUrl'] ?? "").toString(),
      dotHostname: (json['dotHostname'] ?? "").toString(),
      latencyMs: -1,
    );
  }
}
