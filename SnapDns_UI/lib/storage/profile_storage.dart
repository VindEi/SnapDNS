import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/dns_configuration.dart';
import '../core/constants.dart';

class ProfileStorage {
  static Timer? _saveDebounce;

  static Future<List<DnsConfiguration>> load() async {
    try {
      final file = File(AppConstants.profilesFilePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isEmpty) return [];
        final List json = jsonDecode(content);
        return json.map((e) => DnsConfiguration.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint("Error loading profiles: $e");
    }
    return [];
  }

  static void save(List<DnsConfiguration> profiles) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final directory = Directory(AppConstants.appDataPath);
        if (!directory.existsSync()) directory.createSync(recursive: true);

        final json = jsonEncode(profiles.map((e) => e.toJson()).toList());
        final file = File(AppConstants.profilesFilePath);
        final tempFile = File('${AppConstants.profilesFilePath}.tmp');

        // FIX: Atomic Save. Write to temp file first.
        await tempFile.writeAsString(json, flush: true);

        // On Windows, rename throws if the target file already exists, so we delete it first safely
        if (await file.exists()) {
          await file.delete();
        }
        await tempFile.rename(file.path);
      } catch (e) {
        debugPrint("Error saving profiles: $e");
      }
    });
  }
}
