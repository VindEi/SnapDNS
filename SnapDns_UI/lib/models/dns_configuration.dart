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
    // FIX: Dynamic string sanitization helper that strips trailing whitespaces,
    // carriage returns (\r), or tabs from any fields during JSON parsing.
    String sanitize(dynamic val) {
      if (val == null) return "";
      return val.toString().trim();
    }

    var primary = sanitize(json['primaryDns']);
    var nameVal = sanitize(json['name']);

    return DnsConfiguration(
      id: sanitize(json['id'] ?? const Uuid().v4()),
      name: nameVal.isEmpty ? "Unnamed Profile" : nameVal,
      primaryDns: primary,
      secondaryDns: sanitize(json['secondaryDns']),
      ipv6Primary: sanitize(json['ipv6Primary']),
      ipv6Secondary: sanitize(json['ipv6Secondary']),
      dohUrl: sanitize(json['dohUrl']),
      dotHostname: sanitize(json['dotHostname']),
      latencyMs: -1,
    );
  }
}
