# 300X

使用 Flutter 开发的百合会论坛跨平台第三方开源 APP，旨在提供纯净的漫画/小说阅读体验。

![预览](docs/sample/preview.jpg)

当前已实现：

- 百合会论坛登录、图片验证码和 Android/iOS WebView 登录
- 漫画区、轻小说、文学区目录，以及列表/网格、分类和最新/热度筛选
- 高置信标题聚合、帖子目录解析、双向漫画与小说阅读器
- 搜索 10 秒冷却、论坛云收藏、本机历史和阅读进度
- 封面缓存、离线下载、暂停/继续和断网阅读

规格与设计：

- [300X v1 设计规格](docs/spec/yamibox-v1.md)

## Release 构建

可在 [Releases](https://github.com/belleangelina/300X/releases) 下载最新版本，也可自行构建。

```bash
./build_release.sh  # 默认构建 Android
./build_release.sh -p linux
./build_release.sh -p ios   # 需在 macOS/Xcode 环境执行
```

产物统一位于 `build/releases/`。

## 声明

- 本项目与百合会无官方关系。应用只读取登录用户本身有权访问的论坛内容。
- 本项目仅用于学习交流编程技术，严禁将本项目用于商业目的。如有任何商业行为，均与本项目无关。
- 本项目基于 GPLv3 项目 [xiaoyaocz/flutter_dmzj](https://github.com/xiaoyaocz/flutter_dmzj) 修改开发，参考修订为 `6e27f949f2932708f9e2794a3b9e7a6e0e7909ef`。主要修改包括论坛数据源、登录、作品与章节解析、缓存、下载、阅读器交互和多端适配；上游代码版权归原作者及贡献者所有。
- 源代码许可证不覆盖论坛帖子、图片、漫画、小说或翻译内容。论坛内容版权归原作者及相关权利人所有。请遵守论坛规则及内容权利人的要求。

## 许可证

本项目采用 [GPL-3.0-only](LICENSE)。分发二进制时应同时提供与该二进制完全对应的源代码版本和许可证文本。第三方说明见 [NOTICE](NOTICE) 与 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，隐私说明见 [PRIVACY.md](PRIVACY.md)。