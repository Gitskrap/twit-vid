import 'package:flutter_test/flutter_test.dart';
import 'package:xflow/features/update/app_update_service.dart';

Map<String, dynamic> githubRelease({
  String version = '0.26.0',
  bool includeChecksum = true,
  bool prerelease = false,
}) {
  final apkName = 'Twitter-video-$version-arm64.apk';
  final base =
      'https://github.com/Gitskrap/twit-vid/releases/download/v$version/';
  return {
    'tag_name': 'v$version',
    'name': 'Twitter vidéo $version',
    'body': 'Nouvelles fonctionnalités',
    'draft': false,
    'prerelease': prerelease,
    'assets': [
      {
        'name': apkName,
        'browser_download_url': '$base$apkName',
        'size': 63800000,
      },
      if (includeChecksum)
        {
          'name': '$apkName.sha256',
          'browser_download_url': '$base$apkName.sha256',
          'size': 111,
        },
    ],
  };
}

void main() {
  test('numeric semantic versions do not compare lexicographically', () {
    expect(compareAppVersions('0.26.0', '0.25.0'), greaterThan(0));
    expect(compareAppVersions('0.10.0', '0.9.0'), greaterThan(0));
    expect(compareAppVersions('0.26.0', '0.26.0'), 0);
    expect(compareAppVersions('0.25.0', '0.26.0'), lessThan(0));
    expect(compareAppVersions('v0.26.0', '0.25.0'), greaterThan(0));
    expect(compareAppVersions('0.26.0+26', '0.25.0+25'), greaterThan(0));
  });

  test('latest GitHub release resolves only expected ARM64 APK and checksum',
      () {
    final release = AppRelease.fromGitHub(githubRelease());
    expect(release.version, '0.26.0');
    expect(release.apkFileName, 'Twitter-video-0.26.0-arm64.apk');
    expect(release.apkUrl.host, 'github.com');
    expect(release.checksumUrl?.path,
        endsWith('Twitter-video-0.26.0-arm64.apk.sha256'));
    expect(release.apkSize, 63800000);
    expect(release.pageUrl.toString(),
        'https://github.com/Gitskrap/twit-vid/releases/tag/v0.26.0');
  });

  test('old releases without checksum can be listed but not installed', () {
    final release = AppRelease.fromGitHub(
        githubRelease(version: '0.25.0', includeChecksum: false));
    expect(release.checksumUrl, isNull);
  });

  test('reject draft, prerelease, invalid tag, missing APK or foreign host', () {
    expect(() => AppRelease.fromGitHub(githubRelease(prerelease: true)),
        throwsFormatException);
    final malformed = githubRelease()..['tag_name'] = 'not-a-version';
    expect(() => AppRelease.fromGitHub(malformed),
        throwsFormatException);
    final missing = githubRelease()..['assets'] = [];
    expect(() => AppRelease.fromGitHub(missing),
        throwsFormatException);
    final foreign = githubRelease();
    (foreign['assets'] as List).first['browser_download_url'] =
        'https://not-github.example/Twitter-video-0.26.0-arm64.apk';
    expect(() => AppRelease.fromGitHub(foreign),
        throwsFormatException);
  });

  test('SHA-256 checksum parser requires correct filename and 64 hex digits',
      () {
    const digest =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    const name = 'Twitter-video-0.26.0-arm64.apk';
    expect(parseExpectedChecksum('$digest  $name\n', name), digest);
    expect(parseExpectedChecksum('$digest *$name\n', name), digest);
    expect(() => parseExpectedChecksum('$digest  other.apk', name),
        throwsFormatException);
    expect(() => parseExpectedChecksum('bad  $name', name),
        throwsFormatException);
  });
}
