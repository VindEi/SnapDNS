import 'dns_configuration.dart';

class PublicDnsCatalog {
  final String lastUpdated;
  final int count;
  final List<PublicDnsProvider> providers;

  PublicDnsCatalog({
    required this.lastUpdated,
    required this.count,
    required this.providers,
  });

  factory PublicDnsCatalog.fromJson(Map<String, dynamic> json) {
    final rawList = json['providers'] as List? ?? [];
    final List<PublicDnsProvider> parsedProviders = [];

    for (var item in rawList) {
      if (item is Map) {
        parsedProviders
            .add(PublicDnsProvider.fromJson(Map<String, dynamic>.from(item)));
      }
    }

    return PublicDnsCatalog(
      lastUpdated: json['lastUpdated']?.toString() ?? '',
      count:
          json['count'] is int ? json['count'] as int : parsedProviders.length,
      providers: parsedProviders,
    );
  }
}

class PublicDnsProvider {
  final String id;
  final String name;
  final String? website;
  final String country;
  final List<PublicDnsProfile> profiles;

  PublicDnsProvider({
    required this.id,
    required this.name,
    this.website,
    required this.country,
    required this.profiles,
  });

  factory PublicDnsProvider.fromJson(Map<String, dynamic> json) {
    final rawProfiles = json['profiles'] as List? ?? [];
    final List<PublicDnsProfile> parsedProfiles = [];

    for (var item in rawProfiles) {
      if (item is Map) {
        parsedProfiles
            .add(PublicDnsProfile.fromJson(Map<String, dynamic>.from(item)));
      }
    }

    return PublicDnsProvider(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      website: json['website']?.toString(),
      country: json['country']?.toString().toUpperCase() ?? 'GLOBAL',
      profiles: parsedProfiles,
    );
  }
}

class PublicDnsProfile {
  final String id;
  final String name;
  final String primaryCategory;
  final List<String> tags;
  final String? notes;
  final String primaryDns;
  final String secondaryDns;
  final String ipv6Primary;
  final String ipv6Secondary;
  final String dohUrl;
  final String dotHostname;

  PublicDnsProfile({
    required this.id,
    required this.name,
    required this.primaryCategory,
    required this.tags,
    this.notes,
    required this.primaryDns,
    required this.secondaryDns,
    required this.ipv6Primary,
    required this.ipv6Secondary,
    required this.dohUrl,
    required this.dotHostname,
  });

  factory PublicDnsProfile.fromJson(Map<String, dynamic> json) {
    final rawEndpoints = json['endpoints'];
    final Map<String, dynamic> endpoints =
        rawEndpoints is Map ? Map<String, dynamic>.from(rawEndpoints) : {};

    final rawTags = json['tags'] as List? ?? [];

    return PublicDnsProfile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      primaryCategory: json['primaryCategory']?.toString() ?? 'General',
      tags: rawTags.map((t) => t.toString().trim()).toList(),
      notes: json['notes']?.toString(),
      primaryDns: endpoints['primaryDns']?.toString() ?? '',
      secondaryDns: endpoints['secondaryDns']?.toString() ?? '',
      ipv6Primary: endpoints['ipv6Primary']?.toString() ?? '',
      ipv6Secondary: endpoints['ipv6Secondary']?.toString() ?? '',
      dohUrl: endpoints['dohUrl']?.toString() ?? '',
      dotHostname: endpoints['dotHostname']?.toString() ?? '',
    );
  }

  DnsConfiguration toDnsConfiguration(String providerId, String providerName) {
    return DnsConfiguration(
      id: "$providerId-$id",
      name: name,
      group: providerName,
      primaryDns: primaryDns,
      secondaryDns: secondaryDns,
      ipv6Primary: ipv6Primary,
      ipv6Secondary: ipv6Secondary,
      dohUrl: dohUrl,
      dotHostname: dotHostname,
    );
  }
}
