import 'package:flutter_test/flutter_test.dart';
import 'package:snapdns/models/dns_configuration.dart';
import 'package:snapdns/models/public_dns.dart';
import 'package:snapdns/utils/dns_intelligence.dart';

void main() {
  group('DnsConfiguration Model Tests', () {
    test('JSON round-trip preserves all fields', () {
      final original = DnsConfiguration(
        id: 'test-uuid-1234',
        name: 'Custom DNS',
        group: 'Security',
        primaryDns: '1.1.1.1',
        secondaryDns: '1.0.0.1',
        ipv6Primary: '2606:4700:4700::1111',
        ipv6Secondary: '2606:4700:4700::1001',
        dohUrl: 'https://cloudflare-dns.com/dns-query',
        dotHostname: 'one.one.one.one',
      );

      final json = original.toJson();
      final parsed = DnsConfiguration.fromJson(json);

      expect(parsed.id, equals(original.id));
      expect(parsed.name, equals(original.name));
      expect(parsed.group, equals(original.group));
      expect(parsed.primaryDns, equals(original.primaryDns));
      expect(parsed.secondaryDns, equals(original.secondaryDns));
      expect(parsed.ipv6Primary, equals(original.ipv6Primary));
      expect(parsed.ipv6Secondary, equals(original.ipv6Secondary));
      expect(parsed.dohUrl, equals(original.dohUrl));
      expect(parsed.dotHostname, equals(original.dotHostname));
    });

    test('fromJson handles null or empty inputs gracefully', () {
      final parsed = DnsConfiguration.fromJson({});
      expect(parsed.name, equals('Unnamed Profile'));
      expect(parsed.id, isNotEmpty);
      expect(parsed.primaryDns, isEmpty);
      expect(parsed.dohUrl, isEmpty);
    });
  });

  group('PublicDnsCatalog Model Tests', () {
    test('Parses catalog and converts profile to DnsConfiguration', () {
      final catalogJson = {
        'lastUpdated': '2026-11-15',
        'count': 1,
        'providers': [
          {
            'id': 'shecan',
            'name': 'Shecan',
            'website': 'https://shecan.ir',
            'country': 'IR',
            'profiles': [
              {
                'id': 'default',
                'name': 'Shecan Default',
                'primaryCategory': 'Sanction Bypass',
                'tags': ['Anti-Sanction', 'Fast'],
                'endpoints': {
                  'primaryDns': '178.22.122.100',
                  'secondaryDns': '185.51.200.2',
                  'dohUrl': 'https://free.shecan.ir/dns-query',
                  'dotHostname': 'free.shecan.ir',
                }
              }
            ]
          }
        ]
      };

      final catalog = PublicDnsCatalog.fromJson(catalogJson);
      expect(catalog.providers.length, equals(1));

      final provider = catalog.providers.first;
      expect(provider.name, equals('Shecan'));
      expect(provider.profiles.length, equals(1));

      final profile = provider.profiles.first;
      final config = profile.toDnsConfiguration(provider.id, provider.name);

      expect(config.id, equals('shecan-default'));
      expect(config.name, equals('Shecan Default'));
      expect(config.group, equals('Shecan'));
      expect(config.primaryDns, equals('178.22.122.100'));
      expect(config.secondaryDns, equals('185.51.200.2'));
      expect(config.dohUrl, equals('https://free.shecan.ir/dns-query'));
      expect(config.dotHostname, equals('free.shecan.ir'));
    });
  });

  group('DnsIntelligence Import Parsing Tests', () {
    test('Parses JSON array input', () {
      const jsonText = '''
      [
        {
          "name": "Profile 1",
          "primaryDns": "8.8.8.8",
          "secondaryDns": "8.8.4.4"
        },
        {
          "name": "Profile 2",
          "primaryDns": "1.1.1.1",
          "secondaryDns": "1.0.0.1"
        }
      ]
      ''';

      final results = DnsIntelligence.parseImportData(jsonText);
      expect(results.length, equals(2));
      expect(results[0].primaryDns, equals('8.8.8.8'));
      expect(results[1].primaryDns, equals('1.1.1.1'));
    });

    test('Parses unstructured text with IPs and DoH URL', () {
      const rawText = '''
      Here is my DNS server:
      Primary: 94.140.14.14
      Secondary: 94.140.15.15
      DoH: https://dns.adguard-dns.com/dns-query
      dot: dns.adguard-dns.com
      ''';

      final results = DnsIntelligence.parseImportData(rawText);
      expect(results.length, equals(1));
      expect(results.first.primaryDns, equals('94.140.14.14'));
      expect(results.first.secondaryDns, equals('94.140.15.15'));
      expect(results.first.dohUrl, equals('https://dns.adguard-dns.com/dns-query'));
      expect(results.first.dotHostname, equals('dns.adguard-dns.com'));
    });
  });
}
