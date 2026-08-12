import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

Future<void> main(List<String> arguments) async
{
    if (arguments.length != 5)
    {
        stderr.writeln(
            'usage: dart run tool/release/generate_update_manifest.dart '
            '<asset-dir> <version> <build-number> <notes-file> <output>',
        );
        exitCode = 64;
        return;
    }
    final Directory assetDirectory = Directory(arguments[0]);
    final String version = arguments[1];
    final int? buildNumber = int.tryParse(arguments[2]);
    final File notesFile = File(arguments[3]);
    final File output = File(arguments[4]);
    final int? sourceDateEpoch = int.tryParse(
        Platform.environment['SOURCE_DATE_EPOCH'] ?? '',
    );
    if (!assetDirectory.existsSync() ||
        !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) ||
        buildNumber == null ||
        buildNumber <= 0 ||
        !notesFile.existsSync())
    {
        stderr.writeln('invalid manifest input');
        exitCode = 64;
        return;
    }
    final String tag = 'v$version';
    final List<File> files = assetDirectory
        .listSync()
        .whereType<File>()
        .where(
            (File value) =>
                path.canonicalize(value.path) != path.canonicalize(output.path),
        )
        .toList(growable: false)
      ..sort((File left, File right) => left.path.compareTo(right.path));
    final List<Map<String, Object>> artifacts = <Map<String, Object>>[];
    for (final File file in files)
    {
        final String name = path.basename(file.path);
        final (String, String)? identity = _identity(name, version);
        if (identity == null)
        {
            continue;
        }
        artifacts.add(<String, Object>{
            'platform': identity.$1,
            'variant': identity.$2,
            'fileName': name,
            'size': await file.length(),
            'sha256': (await sha256.bind(file.openRead()).first).toString(),
            'githubUrl':
                'https://github.com/belleangelina/300X/releases/download/'
                '$tag/$name',
            'gitcodeUrl':
                'https://api.gitcode.com/api/v5/repos/belleangelina/300X/'
                'releases/$tag/attach_files/$name/download',
        });
    }
    final Set<String> platforms = artifacts
        .map((Map<String, Object> value) => value['platform']! as String)
        .toSet();
    if (!platforms.containsAll(<String>{'android', 'linux', 'ios'}) ||
        artifacts.where(
                (Map<String, Object> value) => value['platform'] == 'android',
            ).length !=
            2)
    {
        stderr.writeln('release assets are incomplete');
        exitCode = 1;
        return;
    }
    final String manifest = const JsonEncoder.withIndent(' ').convert(
        <String, Object>{
              'schemaVersion': 1,
              'versionName': version,
              'buildNumber': buildNumber,
              'releaseNotes': await notesFile.readAsString(),
              'publishedAt': (sourceDateEpoch == null
                      ? DateTime.now().toUtc()
                      : DateTime.fromMillisecondsSinceEpoch(
                          sourceDateEpoch * 1000,
                          isUtc: true,
                      ))
                  .toIso8601String(),
              'artifacts': artifacts,
          },
    );
    await output.writeAsString(
        '$manifest\n',
        flush: true,
    );
}

(String, String)? _identity(String fileName, String version)
{
    final String prefix = 'X300-v$version-';
    if (!fileName.startsWith(prefix))
    {
        return null;
    }
    final String suffix = fileName.substring(prefix.length);
    if (suffix == 'android-universal-release.apk')
    {
        return ('android', 'universal');
    }
    if (suffix == 'android-arm64-v8a-release.apk')
    {
        return ('android', 'arm64-v8a');
    }
    if (suffix == 'ios-unsigned.ipa')
    {
        return ('ios', 'unsigned');
    }
    final RegExpMatch? linux = RegExp(
        r'^linux-(x64|arm64|riscv64)-release\.tar\.gz$',
    ).firstMatch(suffix);
    return linux == null ? null : ('linux', linux.group(1)!);
}
