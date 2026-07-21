import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutPage extends StatelessWidget
{
    const AboutPage({super.key});

    @override
    Widget build(BuildContext context)
    {
        return Scaffold(
            appBar: AppBar(title: const Text('关于APP')),
            body: ListView(
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                    Align(
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.asset(
                                'assets/branding/x300-icon.png',
                                width: 80,
                                height: 80,
                            ),
                        ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                        '300X',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    FutureBuilder<PackageInfo>(
                        future: PackageInfo.fromPlatform(),
                        builder: (
                            BuildContext context,
                            AsyncSnapshot<PackageInfo> snapshot,
                        ) => Text(
                            snapshot.hasData
                                ? 'v${snapshot.data!.version} '
                                    '(${snapshot.data!.buildNumber})'
                                : 'v1.0.0',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                        ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                        '简介',
                        style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                        '300X 是面向百合会论坛的跨平台阅读器，用于整理和阅读当前账号有权访问的漫画与小说。',
                        style: TextStyle(height: 1.6),
                    ),
                    const SizedBox(height: 20),
                    Text(
                        '免责声明',
                        style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                        '300X 是非官方第三方工具，不提供、托管或绕过权限获取论坛内容。'
                        '应用展示的作品、图片和文字版权归原作者及相关权利人所有。'
                        '请遵守百合会论坛规则，仅阅读当前账号有权访问的内容。',
                        style: TextStyle(height: 1.6),
                    ),
                    const SizedBox(height: 20),
                    Text(
                        '开源许可',
                        style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                        '本项目采用 GPL-3.0-only 许可证，基于上游 GPLv3 '
                        '开源项目修改开发。原项目与本项目的版权分别归各自'
                        '贡献者所有，程序不提供任何担保。',
                        style: TextStyle(height: 1.6),
                    ),
                    const SizedBox(height: 8),
                    Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                            onPressed: () => showLicensePage(
                                context: context,
                                applicationName: '300X',
                                applicationIcon: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.asset(
                                        'assets/branding/x300-icon.png',
                                        width: 56,
                                        height: 56,
                                    ),
                                ),
                                applicationLegalese:
                                    'Copyright © 2026 belleangelina\n'
                                    '300X is an independent third-party app.',
                            ),
                            child: const Text('查看开源许可证'),
                        ),
                    ),
                ],
            ),
        );
    }
}
