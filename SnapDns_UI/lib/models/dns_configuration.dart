import 'package:uuid/uuid.dart';

class DnsConfiguration {
  final String id;
  String name;
  String group;
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
    this.group = "",
    this.primaryDns = "",
    this.secondaryDns = "",
    this.ipv6Primary = "",
    this.ipv6Secondary = "",
    this.dohUrl = "",
    this.dotHostname = "",
    this.latencyMs = -1,
  }) : id = (id != null && id.trim().isNotEmpty)
            ? id.trim()
            : const Uuid().v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'group': group,
        'primaryDns': primaryDns,
        'secondaryDns': secondaryDns,
        'ipv6Primary': ipv6Primary,
        'ipv6Secondary': ipv6Secondary,
        'dohUrl': dohUrl,
        'dotHostname': dotHostname,
      };

  factory DnsConfiguration.fromJson(Map<String, dynamic> json) {
    String sanitize(dynamic val) {
      if (val == null) return "";
      return val.toString().trim();
    }

    final rawId = sanitize(json['id']);
    final parsedId = rawId.isNotEmpty ? rawId : const Uuid().v4();
    final nameVal = sanitize(json['name']);
    final groupVal = sanitize(json['group']);

    return DnsConfiguration(
      id: parsedId,
      name: nameVal.isEmpty ? "Unnamed Profile" : nameVal,
      group: groupVal,
      primaryDns: sanitize(json['primaryDns']),
      secondaryDns: sanitize(json['secondaryDns']),
      ipv6Primary: sanitize(json['ipv6Primary']),
      ipv6Secondary: sanitize(json['ipv6Secondary']),
      dohUrl: sanitize(json['dohUrl']),
      dotHostname: sanitize(json['dotHostname']),
      latencyMs: -1,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DnsConfiguration &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
