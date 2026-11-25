import 'package:arman_vpn/app_info.dart';
import 'package:arman_vpn/core/updates.dart';
import 'package:flutter_test/flutter_test.dart';

const _page = 'https://github.com/Amir3M/POL/releases/tag/v1.1.0';
const _download = 'https://github.com/Amir3M/POL/releases/download/v1.1.0';
const _apk = 'amir-vpn-android.apk';
const _installer = 'amir-vpn-windows-setup-x64.exe';
const _portable = 'amir-vpn-windows-x64.zip';
const _linux = 'amir-vpn-linux-x64.tar.gz';

Map<String, Object?> _release({
  String? modifiedFile,
  String? modifiedUrl,
}) => {
  'draft': false,
  'prerelease': false,
  'tag_name': 'v1.1.0',
  'html_url': _page,
  'assets': [
    for (final file in [_apk, _installer, _portable, _linux, 'SHA256SUMS.txt'])
      {
        'name': file,
        'browser_download_url': file == modifiedFile
            ? modifiedUrl
            : '$_download/$file',
        'state': 'uploaded',
        'size': 10,
      },
  ],
};

void main() {
  test('stable AMiR release maps to the correct platform download', () async {
    for (final (os, installed, file) in [
      ('android', false, _apk),
      ('windows', true, _installer),
      ('windows', false, _portable),
      ('linux', false, _linux),
    ]) {
      final release = amirReleaseFromGitHub(
        _release(),
        os: os,
        current: '1.0.0',
      )!;
      expect(release.browserDownloadOnly, isTrue);
      expect(() => release.installSource(os: os), throwsFormatException);
      expect(
        await downloadUrl(
          release,
          os: os,
          installed: installed,
          abi: 'arm64-v8a',
          platformVersion: 'linux_x64',
        ),
        '$_download/$file',
      );
      final cached = releaseFromJson(release.toJson());
      expect(isAmirDownload(cached, os: os, platformVersion: ''), isTrue);
    }
  });

  test('drafts, previews and non-new releases are skipped', () {
    for (final (data, current) in [
      ({..._release(), 'draft': true}, '1.0.0'),
      ({..._release(), 'prerelease': true}, '1.0.0'),
      ({..._release(), 'tag_name': 'v1.1.0-beta'}, '1.0.0'),
      (_release(), '1.1.0'),
      (_release(), '1.1.1'),
    ]) {
      expect(
        amirReleaseFromGitHub(data, os: 'android', current: current),
        isNull,
      );
    }
    expect(
      amirReleaseFromGitHub(
        _release(),
        os: 'linux',
        current: '1.0.0',
        platformVersion: 'linux_arm64',
      ),
      isNull,
    );
  });

  test('rejects the wrong repository or an invalid package URL', () {
    expect(
      () => amirReleaseFromGitHub(
        {..._release(), 'html_url': 'https://github.com/another/POL/releases/tag/v1.1.0'},
        os: 'android',
        current: '1.0.0',
      ),
      throwsFormatException,
    );
    expect(
      () => amirReleaseFromGitHub(
        _release(
          modifiedFile: _apk,
          modifiedUrl: 'https://github.com/another/POL/releases/download/v1.1.0/$_apk',
        ),
        os: 'android',
        current: '1.0.0',
      ),
      throwsFormatException,
    );
    final release = amirReleaseFromGitHub(
      _release(),
      os: 'android',
      current: '1.0.0',
    )!;
    expect(isAmirDownload(release, os: 'linux'), isFalse);
    expect(
      isAmirDownload(
        releaseFromJson({
          ...release.toJson(),
          'release_url': 'https://github.com/another/POL/releases/tag/v1.1.0',
        }),
        os: 'android',
      ),
      isFalse,
    );
  });
}
