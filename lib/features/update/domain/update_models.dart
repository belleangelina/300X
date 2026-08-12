class UpdateArtifact
{
    const UpdateArtifact({
        required this.platform,
        required this.variant,
        required this.fileName,
        required this.size,
        required this.sha256,
        required this.githubUrl,
        required this.gitcodeUrl,
    });

    factory UpdateArtifact.fromJson(Map<String, Object?> json)
    {
        final String platform = _requiredString(json, 'platform');
        final String variant = _requiredString(json, 'variant');
        final String fileName = _requiredString(json, 'fileName');
        final int size = json['size'] is int ? json['size']! as int : 0;
        final String sha256 = _requiredString(json, 'sha256').toLowerCase();
        final Uri githubUrl = Uri.parse(_requiredString(json, 'githubUrl'));
        final Uri gitcodeUrl = Uri.parse(_requiredString(json, 'gitcodeUrl'));
        if (!const <String>{'android', 'ios'}.contains(platform) ||
            variant.isEmpty ||
            !_validFileName(fileName) ||
            size <= 0 ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256) ||
            !_validGithubUrl(githubUrl, fileName) ||
            !_validGitCodeUrl(gitcodeUrl, fileName))
        {
            throw const FormatException('更新清单中的产物信息无效');
        }
        return UpdateArtifact(
            platform: platform,
            variant: variant,
            fileName: fileName,
            size: size,
            sha256: sha256,
            githubUrl: githubUrl,
            gitcodeUrl: gitcodeUrl,
        );
    }

    final String platform;
    final String variant;
    final String fileName;
    final int size;
    final String sha256;
    final Uri githubUrl;
    final Uri gitcodeUrl;

    static bool _validFileName(String value)
    {
        return value.isNotEmpty &&
            !value.contains('/') &&
            !value.contains('\\') &&
            value != '.' &&
            value != '..';
    }

    static bool _validGithubUrl(Uri value, String fileName)
    {
        return value.scheme == 'https' &&
            value.host == 'github.com' &&
            value.path.startsWith(
                '/belleangelina/300X/releases/download/',
            ) &&
            value.pathSegments.isNotEmpty &&
            value.pathSegments.last == fileName &&
            !value.hasQuery &&
            !value.hasFragment;
    }

    static bool _validGitCodeUrl(Uri value, String fileName)
    {
        return value.scheme == 'https' &&
            const <String>{'gitcode.com', 'api.gitcode.com'}.contains(
                value.host,
            ) &&
            value.path.contains('/belleangelina/300X/') &&
            (value.pathSegments.isNotEmpty &&
                    value.pathSegments.last == fileName ||
                value.pathSegments.length >= 2 &&
                    value.pathSegments[value.pathSegments.length - 2] ==
                        fileName &&
                    value.pathSegments.last == 'download') &&
            !value.hasQuery &&
            !value.hasFragment;
    }
}

class UpdateManifest
{
    const UpdateManifest({
        required this.versionName,
        required this.buildNumber,
        required this.releaseNotes,
        required this.publishedAt,
        required this.artifacts,
    });

    factory UpdateManifest.fromJson(Map<String, Object?> json)
    {
        if (json['schemaVersion'] != 1)
        {
            throw const FormatException('不支持的更新清单版本');
        }
        final String versionName = _requiredString(json, 'versionName');
        final Object? buildValue = json['buildNumber'];
        final int buildNumber = buildValue is int ? buildValue : 0;
        final String releaseNotes = json['releaseNotes'] is String
            ? json['releaseNotes']! as String
            : '';
        final DateTime? publishedAt = DateTime.tryParse(
            _requiredString(json, 'publishedAt'),
        );
        final Object? artifactValue = json['artifacts'];
        if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(versionName) ||
            buildNumber <= 0 ||
            publishedAt == null ||
            artifactValue is! List<Object?> ||
            artifactValue.isEmpty)
        {
            throw const FormatException('更新清单信息不完整');
        }
        final List<UpdateArtifact> artifacts = artifactValue.map(
            (Object? value)
            {
                if (value is! Map<String, Object?>)
                {
                    throw const FormatException('更新产物格式无效');
                }
                return UpdateArtifact.fromJson(value);
            },
        ).toList(growable: false);
        final Set<String> identities = artifacts
            .map((UpdateArtifact value) => '${value.platform}:${value.variant}')
            .toSet();
        if (identities.length != artifacts.length)
        {
            throw const FormatException('更新清单包含重复产物');
        }
        return UpdateManifest(
            versionName: versionName,
            buildNumber: buildNumber,
            releaseNotes: releaseNotes,
            publishedAt: publishedAt.toUtc(),
            artifacts: artifacts,
        );
    }

    final String versionName;
    final int buildNumber;
    final String releaseNotes;
    final DateTime publishedAt;
    final List<UpdateArtifact> artifacts;

    UpdateArtifact? artifactFor(String platform, String variant)
    {
        for (final UpdateArtifact artifact in artifacts)
        {
            if (artifact.platform == platform && artifact.variant == variant)
            {
                return artifact;
            }
        }
        return null;
    }
}

String _requiredString(Map<String, Object?> json, String key)
{
    final Object? value = json[key];
    if (value is! String || value.trim().isEmpty)
    {
        throw FormatException('更新清单缺少 $key');
    }
    return value.trim();
}
