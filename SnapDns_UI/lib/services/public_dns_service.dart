import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../core/constants.dart';
import '../models/public_dns.dart';

class PublicDnsService {
  static const Duration requestTimeout = Duration(seconds: 8);

  static const String _cdnUrl =
      'https://cdn.jsdelivr.net/gh/VindEi/public-dns-directory@data/index.json';
  static const String _rawFallbackUrl =
      'https://raw.githubusercontent.com/VindEi/public-dns-directory/data/index.json';

  static String get _cacheFilePath =>
      p.join(AppConstants.appDataPath, 'public_dns_cache.json');

  static Future<PublicDnsCatalog?> loadCachedCatalog() async {
    try {
      final file = File(_cacheFilePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final decoded = jsonDecode(content);
          if (decoded is Map) {
            return PublicDnsCatalog.fromJson(
                Map<String, dynamic>.from(decoded));
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<PublicDnsCatalog?> fetchLatestCatalog() async {
    PublicDnsCatalog? result = await _fetchFromUrl(_cdnUrl);
    result ??= await _fetchFromUrl(_rawFallbackUrl);
    return result;
  }

  static Future<PublicDnsCatalog?> _fetchFromUrl(String url) async {
    try {
      final response = await http.get(Uri.parse(url),
          headers: {'User-Agent': 'SnapDNS-App'}).timeout(requestTimeout);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          final catalog =
              PublicDnsCatalog.fromJson(Map<String, dynamic>.from(decoded));
          await _writeAtomicCache(response.body);
          return catalog;
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _writeAtomicCache(String content) async {
    try {
      final targetFile = File(_cacheFilePath);
      final tempFile = File('$_cacheFilePath.tmp');
      await tempFile.writeAsString(content, flush: true);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetFile.path);
    } catch (_) {}
  }
}
