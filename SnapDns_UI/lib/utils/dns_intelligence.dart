import '../models/dns_configuration.dart';

class DnsIntelligence {
  static final List<DnsConfiguration> defaultProfiles = [
    DnsConfiguration(
      name: "Cloudflare",
      primaryDns: "1.1.1.1",
      secondaryDns: "1.0.0.1",
      ipv6Primary: "2606:4700:4700::1111",
      ipv6Secondary: "2606:4700:4700::1001",
      dohUrl: "https://cloudflare-dns.com/dns-query",
      dotHostname: "one.one.one.one",
    ),
    DnsConfiguration(
      name: "Google",
      primaryDns: "8.8.8.8",
      secondaryDns: "8.8.4.4",
      ipv6Primary: "2001:4860:4860::8888",
      ipv6Secondary: "2001:4860:4860::8844",
      dohUrl: "https://dns.google/dns-query",
      dotHostname: "dns.google",
    ),
    DnsConfiguration(
      name: "Quad9",
      primaryDns: "9.9.9.9",
      secondaryDns: "149.112.112.112",
      ipv6Primary: "2620:fe::fe",
      ipv6Secondary: "2620:fe::9",
      dohUrl: "https://dns.quad9.net/dns-query",
      dotHostname: "dns.quad9.net",
    ),
    DnsConfiguration(
      name: "AdGuard",
      primaryDns: "94.140.14.14",
      secondaryDns: "94.140.15.15",
      ipv6Primary: "2a10:50c0::ad1:ff",
      ipv6Secondary: "2a10:50c0::ad2:ff",
      dohUrl: "https://dns.adguard-dns.com/dns-query",
      dotHostname: "dns.adguard-dns.com",
    ),
  ];

  static DnsConfiguration? parseHumanText(String input) {
    final ipv4Regex = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');
    final ipv6Regex = RegExp(
      r'(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|:(:[0-9a-fA-F]{1,4}){1,7})',
    );
    final urlRegex = RegExp(r'https?://[^\s/$.?#].[^\s]*');
    final dotRegex = RegExp(
      r'(?:dot|tls|host):\s*([a-zA-Z0-9.-]+)',
      caseSensitive: false,
    );

    final ipv4s = ipv4Regex.allMatches(input).map((m) => m.group(0)!).toList();
    final ipv6s = ipv6Regex.allMatches(input).map((m) => m.group(0)!).toList();
    final urls =
        urlRegex.allMatches(input).map((m) => _cleanUrl(m.group(0)!)).toList();
    final dots = dotRegex.allMatches(input).map((m) => m.group(1)!).toList();

    if (ipv4s.isEmpty && ipv6s.isEmpty && urls.isEmpty && dots.isEmpty) {
      return null;
    }

    // FIX: Trim all parsed regex outputs to prevent capturing whitespaces or raw carriage returns
    return DnsConfiguration(
      name: "Imported Profile",
      primaryDns: ipv4s.isNotEmpty ? ipv4s[0].trim() : "",
      secondaryDns: ipv4s.length > 1 ? ipv4s[1].trim() : "",
      ipv6Primary: ipv6s.isNotEmpty ? ipv6s[0].trim() : "",
      ipv6Secondary: ipv6s.length > 1 ? ipv6s[1].trim() : "",
      dohUrl: urls.isNotEmpty ? urls[0].trim() : "",
      dotHostname: dots.isNotEmpty ? dots[0].trim() : "",
    );
  }

  static String _cleanUrl(String url) {
    return url.replaceAll(RegExp(r'["\x27,;\}$\]]+$'), '').trim();
  }

  static String formatForSharing(DnsConfiguration c) {
    final v4 = c.secondaryDns.isNotEmpty
        ? "${c.primaryDns} / ${c.secondaryDns}"
        : (c.primaryDns.isEmpty ? 'AUTO' : c.primaryDns);
    final v6 = c.ipv6Secondary.isNotEmpty
        ? "${c.ipv6Primary} / ${c.ipv6Secondary}"
        : (c.ipv6Primary.isEmpty ? 'DISABLED' : c.ipv6Primary);

    return """
┌─ SNAPDNS PROFILE ──────────
│ NAME: ${c.name.toUpperCase()}
│ IPv4: $v4
│ IPv6: $v6
│ DoH : ${c.dohUrl.isEmpty ? 'DISABLED' : c.dohUrl}
│ DoT : ${c.dotHostname.isEmpty ? 'DISABLED' : c.dotHostname}
└────────────────────────────""";
  }
}
