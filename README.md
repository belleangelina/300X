# 300X

使用 Flutter 开发的百合会论坛跨平台第三方开源 APP，提供纯净的漫画/小说阅读体验。

![预览](docs/sample/preview.jpg)

当前已实现：

- 百合会论坛登录、图片验证码和 Android/iOS WebView 登录
- 漫画区、轻小说、文学区目录，以及列表/网格、分类和最新/热度筛选
- 高置信标题聚合、帖子目录解析、双向漫画与小说阅读器
- 搜索 10 秒冷却、论坛云收藏、本机历史和阅读进度
- 封面缓存、离线下载、暂停/继续和断网阅读
- Android/iOS 后台检查更新，Android 支持应用内下载、校验并调用系统安装器

## Release 构建

正式发布仅提供 Android 和 iOS 产物，可从
[GitHub Releases](https://github.com/belleangelina/300X/releases) 或
[GitCode 官方镜像](https://gitcode.com/belleangelina/300X/releases) 下载。Android
提供通用 APK 和 `arm64-v8a` APK；iOS 提供未签名 IPA，需要自行签名，
或在受支持的设备上通过 TrollStore 安装。

也可以在本地自行构建：

```bash
./build_release.sh -p android
./build_release.sh -p ios   # 需在 macOS/Xcode 环境执行
./build_release.sh -p linux # 仅用于本地开发与验证，不正式发布
```

产物统一位于 `build/releases/`。

Linux 版使用系统 WebKitGTK 完成论坛要求的 JavaScript 安全验证。Ubuntu
22.04 构建环境需要安装 `libwebkit2gtk-4.0-dev`，运行 Release bundle 需要
系统提供 `libwebkit2gtk-4.0-37`。

## 声明

- 本项目与百合会无官方关系。应用只读取登录用户本身有权访问的论坛内容。
- 本项目仅用于学习交流编程技术，严禁将本项目用于商业目的。如有任何商业行为，均与本项目无关。
- 本项目基于 GPLv3 项目 [xiaoyaocz/flutter_dmzj](https://github.com/xiaoyaocz/flutter_dmzj) 修改开发，参考修订为 `6e27f949f2932708f9e2794a3b9e7a6e0e7909ef`。主要修改包括论坛数据源、登录、作品与章节解析、缓存、下载、阅读器交互和多端适配；上游代码版权归原作者及贡献者所有。
- 源代码许可证不覆盖论坛帖子、图片、漫画、小说或翻译内容。论坛内容版权归原作者及相关权利人所有。请遵守论坛规则及内容权利人的要求。

## 许可证

本项目采用 [GPL-3.0-only](LICENSE)。分发二进制时应同时提供与该二进制完全对应的源代码版本和许可证文本。第三方说明见 [NOTICE](NOTICE) 与 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，隐私说明见 [PRIVACY.md](PRIVACY.md)。
