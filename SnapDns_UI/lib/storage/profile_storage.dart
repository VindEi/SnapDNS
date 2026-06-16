import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/dns_configuration.dart';
import '../core/constants.dart';

class ProfileStorage {
  static Future<List<DnsConfiguration>> load() async {
    final file = File(AppConstants.profilesFilePath);
    final backupFile = File('${AppConstants.profilesFilePath}.bak');

    Future<List<DnsConfiguration>?> tryLoad(File f) async {
      try {
        if (await f.exists()) {
          final content = await f.readAsString();
          if (content.trim().isEmpty) return [];
          final List json = jsonDecode(content);
          return json.map((e) => DnsConfiguration.fromJson(e)).toList();
        }
      } catch (e) {
        debugPrint("Error reading/parsing ${f.path}: $e");
      }
      return null;
    }

    var profiles = await tryLoad(file);
    if (profiles != null) return profiles;

    profiles = await tryLoad(backupFile);
    if (profiles != null) {
      debugPrint("Recovered DNS profiles from backup file.");
      try {
        await backupFile.copy(file.path);
      } catch (_) {}
      return profiles;
    }

    return [];
  }

  // FIX: Removed redundant debounce timer.
  // Profile edits/deletions are discrete clicks, not key inputs. Writing instantly eliminates data loss on exit.
  static Future<void> save(List<DnsConfiguration> profiles) async {
    try {
      final directory = Directory(AppConstants.appDataPath);
      if (!directory.existsSync()) directory.createSync(recursive: true);

      final json = jsonEncode(profiles.map((e) => e.toJson()).toList());
      final file = File(AppConstants.profilesFilePath);
      final tempFile = File('${AppConstants.profilesFilePath}.tmp');
      final backupFile = File('${AppConstants.profilesFilePath}.bak');

      await tempFile.writeAsString(json, flush: true);

      if (await file.exists()) {
        if (await backupFile.exists()) {
          await backupFile.delete();
        }
        await file.rename(backupFile.path);
      }

      await tempFile.rename(file.path);

      if (await backupFile.exists()) {
        await backupFile.delete();
      }
    } catch (e) {
      debugPrint("Error saving profiles: $e");
    }
  }
}
