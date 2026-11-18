import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Public GitHub releases: never bundle authentication tokens into the APK.
const githubReleaseApi =
    'https://api.github.com/repos/Gitskrap/twit-vid/releases/latest';

const _channel = MethodChannel('fr.twittervideo.client/updates');

class InstalledAppVersion {
  const InstalledAppVersion(this.name, this.code);
  final String name;
  final int code;
}

class AppRelease {
  const AppRelease({
    required this.version,
    required this.title,
    required this.notes,
    required this.apkUrl,
    required this.apkFileName,
    required this.apkSize,
    required this.checksumUrl,
    required this.pageUrl,
  });

  final String version;
  final String title;
  final String notes;
  final Uri apkUrl;
  final String apkFileName;
  final int apkSize;
  final Uri? checksumUrl;
  final Uri pageUrl;

  factory AppRelease.fromGitHub(Map<String, dynamic> json) {
    if (json['draft'] == true || json['prerelease'] == true) {
      throw const FormatException('Version non publiée');
    }
    final rawTag = json['tag_name']?.toString() ?? '';
    final version = rawTag.startsWith('v') ? rawTag.substring(1) : rawTag;
    parseVersionParts(version);
    final apkName = 'Twitter-video-' + version + '-arm64.apk';
    final checksumName = apkName + '.sha256';
    final assets = (json['assets'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    Map<String, dynamic>? asset(String name) {
      for (final item in assets) {
        if (item['name'] == name) return item;
      }
      return null;
    }

    final apk = asset(apkName);
    if (apk == null) {
      throw FormatException('APK ARM64 absent de la version ' + version);
    }
    Uri trustedAsset(Map<String, dynamic> data) {
      final uri =
          Uri.tryParse(data['browser_download_url']?.toString() ?? '');
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'github.com' ||
          uri.path !=
              '/Gitskrap/twit-vid/releases/download/v' +
                  version +
                  '/' +
                  data['name'].toString()) {
        throw const FormatException('Adresse de téléchargement inattendue');
      }
      return uri;
    }

    final checksum = asset(checksumName);
    return AppRelease(
      version: version,
      title: json['name']?.toString() ?? 'Twit Vid ' + version,
      notes: json['body']?.toString() ?? '',
      apkUrl: trustedAsset(apk),
      apkFileName: apkName,
      apkSize: (apk['size'] as num?)?.toInt() ?? 0,
      checksumUrl: checksum == null ? null : trustedAsset(checksum),
      pageUrl: Uri.https('github.com',
          '/Gitskrap/twit-vid/releases/tag/v' + version),
    );
  }
}

List<int> parseVersionParts(String value) {
  final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$')
      .firstMatch(value.trim());
  if (match == null) {
    throw FormatException('Numéro de version invalide : ' + value);
  }
  return [
    for (var i = 1; i <= 3; i++) int.parse(match.group(i)!),
  ];
}

int compareAppVersions(String a, String b) {
  final first = parseVersionParts(a);
  final second = parseVersionParts(b);
  for (var i = 0; i < first.length; i++) {
    final result = first[i].compareTo(second[i]);
    if (result != 0) return result;
  }
  return 0;
}

/// SHA-256 text is published alongside the APK by the GitHub release workflow.
String parseExpectedChecksum(String content, String expectedFile) {
  final match = RegExp(r'^([a-fA-F0-9]{64})\s+\*?([^\s]+)$')
      .firstMatch(content.trim());
  if (match == null || match.group(2) != expectedFile) {
    throw const FormatException('Empreinte SHA-256 invalide');
  }
  return match.group(1)!.toLowerCase();
}

class AppUpdateService {
  Future<InstalledAppVersion> getInstalledVersion() async {
    final details =
        await _channel.invokeMapMethod<String, dynamic>('getInstalledVersion');
    if (details == null) {
      throw StateError('Version Android indisponible');
    }
    return InstalledAppVersion(
      details['name']?.toString() ?? '0.0.0',
      (details['code'] as num?)?.toInt() ?? 0,
    );
  }

  Future<AppRelease> getLatestRelease() async {
    final response = await http.get(
      Uri.parse(githubReleaseApi),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Twit-Vid-Android-Updater',
      },
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw HttpException(
          'GitHub indisponible (HTTP ' + response.statusCode.toString() + ')');
    }
    return AppRelease.fromGitHub(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>);
  }

  Future<bool> hasUpdate(AppRelease release) async {
    final current = await getInstalledVersion();
    return compareAppVersions(release.version, current.name) > 0;
  }

  /// Download stream to private cache and verify GitHub's SHA-256 checksum.
  Future<File> downloadVerifiedApk(
    AppRelease release, {
    void Function(double fraction)? onProgress,
  }) async {
    final checksumUrl = release.checksumUrl;
    if (checksumUrl == null) {
      throw const FormatException(
        'Cette version ne publie pas de fichier SHA-256.',
      );
    }
    final checksumResponse =
        await http.get(checksumUrl).timeout(const Duration(seconds: 20));
    if (checksumResponse.statusCode != 200 ||
        checksumResponse.bodyBytes.length > 4096) {
      throw const HttpException('Vérification GitHub indisponible');
    }
    final expected = parseExpectedChecksum(
        utf8.decode(checksumResponse.bodyBytes), release.apkFileName);
    final cache = Directory(
        (await getTemporaryDirectory()).path + '/app-updates');
    await cache.create(recursive: true);
    final file = File(cache.path + '/' + release.apkFileName);
    if (await file.exists()) await file.delete();

    final client = http.Client();
    IOSink? output;
    try {
      final request = http.Request('GET', release.apkUrl);
      request.headers['User-Agent'] = 'Twit-Vid-Android-Updater';
      final response = await client.send(request)
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw HttpException('Téléchargement impossible (HTTP ' +
            response.statusCode.toString() + ')');
      }
      const maxSize = 300 * 1024 * 1024;
      if (release.apkSize > maxSize) {
        throw const FormatException('APK anormalement volumineux');
      }
      final expectedSize =
          release.apkSize > 0 ? release.apkSize : response.contentLength ?? 0;
      var received = 0;
      Digest? actualDigest;
      final digestSink =
          ChunkedConversionSink<Digest>.withCallback((values) {
        actualDigest = values.single;
      });
      final hasher = sha256.startChunkedConversion(digestSink);
      output = file.openWrite();
      await for (final chunk in response.stream) {
        received += chunk.length;
        if (received > maxSize) {
          throw const FormatException('APK dépassant la limite autorisée');
        }
        hasher.add(chunk);
        output.add(chunk);
        if (expectedSize > 0) {
          onProgress?.call((received / expectedSize).clamp(0.0, 1.0));
        }
      }
      await output.flush();
      await output.close();
      output = null;
      hasher.close();

      if (received == 0 ||
          (release.apkSize > 0 && received != release.apkSize)) {
        throw const FormatException('Téléchargement incomplet');
      }
      if (actualDigest.toString().toLowerCase() != expected) {
        throw const FormatException(
            'Empreinte SHA-256 incorrecte : installation annulée');
      }
      onProgress?.call(1.0);
      return file;
    } catch (_) {
      if (output != null) await output.close();
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<bool> canInstallPackages() async =>
      await _channel.invokeMethod<bool>('canInstallPackages') ?? false;

  Future<void> openInstallPermissionSettings() =>
      _channel.invokeMethod<void>('openInstallPermissionSettings');

  /// Android presents its standard installer: silent installs aren't possible.
  Future<void> installVerifiedApk(File apk) =>
      _channel.invokeMethod<void>('installApk', {'path': apk.path});
}
