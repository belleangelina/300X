# 300X V2 开发交接状态

> 最后同步：2026-08-14。业务节点 `ae79258`，验证包版本记在 `fa332e1`（`1.0.5+9`）。其后若只有文档校正，以 `git log` 为准。这不是 V2 正式发布，Android/iOS 发布门禁仍未做。本文只记录脱敏工程状态，不保存账号、Cookie、`formhash`、帖子正文或私信内容。每完成一个可验证节点都必须更新本文；新会话应先读本文，再读 `docs/spec/yamibox-v2.md`、`docs/spec/yamibox-v2-capabilities.md`。若要在 Linux 点界面，必读 `docs/engineering/linux-debug-ui.md`，不要用 xdotool。当前工作树为最终事实。

## 当前目标与边界

- 工作分支：当前检出 `feature/v2.0-bk`，本地无远程跟踪。`feature/v2.0` 仍停在 `e7cad52`。基于当前 V1 基线选择性实现 V2；禁止整体合并旧 `feature/full-forum`。未经用户要求不要 push。
- 权威规格：`docs/spec/yamibox-v2.md`；逐能力状态：`docs/spec/yamibox-v2-capabilities.md`；用户实测：`docs/validation/yamibox-v2-manual-checklist.md`。
- 论坛结构、权限、动态字段和流程以真实移动网页为准，不使用电脑网页或旧分支扩大范围。
- 未经本轮用户明确授权，禁止自动真实站探针、业务 POST、写操作入口、通知/私信正文、注销/切号。Linux 只读实机（启动已有会话的 Debug 包、按 Key 点击、截图）以本文「当前节点」和 `docs/engineering/linux-debug-ui.md` 为准，不要退回 xdotool。Android/iOS 实机仍由用户执行。
- 子代理可用于只读勘察、缺陷审查和文件集合互不重叠的实现；同一文件同一时间只允许一个写入者。子代理不得做真实站请求、不得改文档结论、不得整文件覆盖平台桥。
- 不可靠或未取得标准移动合同的写操作必须 fail closed，不得凭 URL、文案或桌面网页猜实现。
- 业务改动已提交。工作树只应看到未跟踪的 Gradle `.uuid`（不要加入版本库）。不要覆盖、回退或格式化无关文件；修改前先检查 `git status`、近期文件时间和并行任务范围。

## 当前节点

目标：已向用户提供 `1.0.5+9` Android Release 验证包，不是 V2 正式版。

- Debug 包在 `kDebugMode` 下于 `127.0.0.1` 提供按 Flutter `Key` 的 find/wait/tap/enter/back；Release 不启动。
- Linux 实机已用该入口完成：四主入口、论坛首页、管理版、本版搜索（只输入未提交）、社区菜单、本人资料、好友空列表、访客列表、打开主题。未再用 xdotool 点业务控件。
- 本人资料「收藏」入口工具判定点中，页面未打开，仍未验列表。
- 未提交任何写操作，未打开通知/私信。

Linux 上还可以补的只读路径（非发布门禁）：本人资料「收藏」列表、`findpost`、附件下载/打开、主题或多页版块的下一页、离线缓存、在线成员/足迹页签、他人资料、群组/日志/相册收藏页。不要做：任何写入、通知/私信正文、注销/切号、本版搜索提交（未授权）。

下一动作：等用户用 `1.0.5+9` 验证包跑 Android 清单并回传结果。不要把本次构建当成 V2 发布。若继续 Linux 只读，用 `docs/engineering/linux-debug-ui.md`。

## 已完成的主要基础

- 四主入口与首页/收藏重组；收藏顶部为“漫画 / 小说 / 全部”，原始收藏分类动态读取。
- 论坛首页、分区、版块、动态筛选/分页、公告、主题连续楼层、正文结构、点评/评分摘要、搜索、`findpost`、阅读桥和离线只读缓存。
- 群组版块/分类、日志、相册等异构收藏原生只读路径。
- 通知、私信、资料、本人主题/回复、好友、在线成员和访客等社区读取；私信发送/回复原生管线。
- 发主题、普通回复、引用、编辑、主题收藏/取消和站内分享七类严格动态表单管线；持久提交封存数据库 schema v9；回复按 tid、引用/编辑按 pid 归一防重。
- 论坛/收藏/搜索缓存、草稿、Cookie 和提交封存按 uid 隔离；WebView 身份切换、崩溃恢复和 WAF 锁序已有自动化。
- Android 原页系统文件选择器已接入，只打开已有文件，接受 `content://` 只读 URI，不支持保存、相机或自动上传；独立 6 项测试和静态检查已复核通过。
- WebView Cookie 属性安全桥已接入 WebLogin 和 ForumOriginalPage。iOS 使用 `WKHTTPCookieStore` 回读完整属性；Android 因系统 `CookieManager.getCookie` 只返回 `name=value`，继承进入前已知属性，新认证 Cookie 使用 `Secure + HttpOnly + SameSite=Strict` 安全默认，同名作用域歧义失败关闭，WAF Cookie 保持脚本可读但强制 Secure。
- 版块收藏已使用独立安全管线：添加在唯一 fresh `handlekey` 的 GET 前原子落 attempted 封存，取消严格解析 GET 确认页和四个原样字段后才在 POST 前封存；跨实例 claim 只放行一次，两类结果均完整遍历当前 uid 的 `type=forum` 全部分页后确认，未知结果保留封存并支持只读回读或人工解除。缓存页不暴露添加/取消入口。
- 论坛搜索已保留移动响应中的精确作者资料 URI，解析、缓存和点击前均绑定同一正 `uid`，搜索结果可进入原生个人资料。
- 版块主题列表已保留精确移动作者资料 URI，并在解析与离线缓存中绑定同一正 `uid`；可信入口显示独立作者按钮并进入原生资料页，漂移或恶意链接只保留作者文字。公告或没有资料合同的条目不显示空入口。
- 主题楼层、点评和评分作者使用同一合同：仅 `authorUri != null` 且正 `uid` 显示独立按钮，默认 `Navigator.push(CommunityProfileScreen)`，不替换横屏论坛右栏。未知 community 入口仍关闭。
- 本人资料页收藏入口已接到原生全部收藏；`canOpenFor` 要求 `profileUserId == viewerUserId`，URI 必须是同源 `do=favorite` 移动页。他人收藏和未知入口保持禁用。
- 公告正文 `download` 使用与主题相同的认证下载控制器；仓库 Referer 接受 `mod=announcement` 且 `id` 为正、query 仅 `mod/id/mobile` 的公告页。
- 横屏主壳的左侧列表和右侧详情均按“漫画/小说、论坛、收藏、我的”四入口独立保活。切换主入口只改变可见索引，不销毁已打开的版块、主题、作品、异构收藏或个人二级页；隐藏详情停用 ticker，返回时不重复触发初始加载。
- 原始收藏中已经由 `FavoriteTargetContract` 严格识别的 `userSpace` 目标现接入原生个人资料页，窄屏使用完整路由、横屏使用收藏入口自己的保活右栏；URI 必须是同源 HTTPS、唯一正 `uid` 和 `mobile=2`，未知 `community` 类型仍保持不可执行。
- 受保护附件下载已接入：`ForumAttachmentRepository` 在当前 uid 会话租约内校验身份、只允许同源附件路由、跳转必须同一 `aid` 或同一 `/data/attachment` 路径、256MB 上限、流式原子落盘、跨实例单飞、账号代际取消。默认缓存根为 `getApplicationCacheDirectory`（iOS/Android 即 Caches/`cacheDir`）。主题页模型附件和正文 `download` 链接都走 `ForumAttachmentDownloadController`；本地文件被清理后点按会重新下载，失败不 `launchUrl` 远程附件。Android/iOS 打开通道仅暴露 `forum-attachments` 下已解析文件，Cookie 通道独立保留。

上述“已完成”仅表示对应代码/自动化已存在；实际平台与真实业务写入状态必须以能力台账为准，不能概括为 V2 已完成。

## 当前并行修改所有权

- 无并行子任务占用文件。版块收藏、Cookie 属性桥、附件下载和主题作者接线均已回到主线。
- 平台文件 `MainActivity.kt`、`AppDelegate.swift`、`update_file_paths.xml` 同时服务文件选择、Cookie 和附件打开。后续只做小范围追加，禁止整文件覆盖，必须保留 `com.yamibox300/forum_web_cookies` 与 `com.yamibox300/forum_downloaded_file` 两个独立通道。
- 本节点未再改平台文件。后续若改 Topic 页或附件仓库，先看 `git status`。
- Linux 实机不要再用 xdotool 点业务控件；用 `docs/engineering/linux-debug-ui.md`。Debug 包退出后回环端口即关闭。

## 已知风险与明确未完成

- 2026-08-13 将两个版块收藏添加入口误当只读 GET，真实账号因此意外新增两条版块收藏。不得自动删除；用户需在移动网页“收藏 → 版块”按标题核对后逐条取消。不要再自动请求任一添加入口。
- 删除、投票、点评写入、评分写入和举报没有已验证标准移动合同，当前保持无原生可执行入口。
- 附件上传尚无完整 multipart、限制、结果和恢复合同；动态表单只识别文件字段并在 POST/封存前拒绝附件。Android 原页选择器代码存在不等于上传闭环。
- 完整评分页、删除、投票、点评写入、评分写入、举报、附件上传和他人收藏没有可执行原生入口。
- 附件登录页只按 `Content-Type: text/html` / `application/xhtml+xml` 识别；声明为 `octet-stream` 的 HTML 仍可能被当文件落下。
- 真实站 `aid` 若仍是 Discuz 编码串而不是正整数，当前严格合同会失败关闭。禁止为此再打真实站探针。
- 普通回复、引用和编辑没有已验证成功响应合同；非明确失败必须保持 `resultUnknown`，只读回读不能自动判成功、删草稿或解除封存。
- 所有论坛业务 POST 均未在真实站验证；Android/iOS 全路径均未实机验证。
- iOS 在当前 Linux 环境不能执行 Xcode 构建；只能做 Dart/源码静态检查，最终由用户实机和 macOS 构建验收。
- Android 没有公开 API 可完整回读 WebView Cookie 的 Domain/Path/Secure/HttpOnly/Expires/SameSite；当前保守合并是安全边界而非平台已验证的属性完全等价，需用户实机验证登录、过期、登出、WAF 和切号。

## 最近可信证据

- 验证用 Android Release `1.0.5+9`（`--keep-version`，只加构建号）：`build/releases/X300-v1.0.5-android-arm64-v8a-release.apk`、`build/releases/X300-v1.0.5-android-universal-release.apk`。日志：`.artifacts/validation/logs/v2-android-release-1.0.5-build9.log`。不是正式发布。
- Linux Debug 按 Key 点击：`docs/engineering/linux-debug-ui.md`；试跑 `.artifacts/validation/v2-debug-ui-linux/REPORT.md`。测试 `.artifacts/validation/logs/v2-debug-ui-and-key-regression.log`；构建 `.artifacts/validation/logs/v2-debug-ui-linux-debug-build.log`。
- Linux 只读实机（xdotool 轮次）：`.artifacts/validation/v2-linux-readonly-2026-08-14/REPORT.md`。公告 URI 与跨版置顶修复测试：`.artifacts/validation/logs/v2-linux-announcement-uri-normalize-test.log`、`v2-linux-fid-sticky-and-announcement-test.log`。
- 15.4 入口分类：删除/投票/举报明确不适用；点评/评分写入为 Android/iOS 受控原页；主题页定向测试见 `.artifacts/validation/logs/v2-original-action-classification-test.log`。
- 空入口接线：`.artifacts/validation/logs/v2-empty-entry-wiring-tests.log`。含本人/他人资料收藏、公告附件 Referer、公告页认证下载、社区解析收藏 kind、主题页回归。
- fail closed + resultUnknown：`.artifacts/validation/logs/v2-fail-closed-and-wiring-tests.log`、`v2-result-unknown-tests.log`。含七类已验证 Action、删除未注册、附件 POST 拒绝、未知结果不重发、回读不解除封存。
- V1 受影响回归：`.artifacts/validation/logs/v2-v1-regression.log`。漫画/小说入口、详情、阅读、下载、历史、设置、应用内更新、HomeShell。
- 定向 analyze：`.artifacts/validation/logs/v2-empty-entry-wiring-analyze.log`。
- 主题作者 + 附件定向：`.artifacts/validation/logs/v2-topic-author-attachment-focused.log`、`v2-attachment-inline-and-author-retest.log`。
- Linux Debug 构建通过：`.artifacts/validation/logs/v2-attachment-author-linux-debug-build.log`。
- Android Debug 构建通过：`.artifacts/validation/logs/v2-attachment-author-android-debug-build.log`。
- 版块收藏非典型合同证据：`.artifacts/validation/logs/v2-favorite-board-interaction-live-probe.log`。禁止重跑真实站探针。

日志存在不等于覆盖当前工作树。使用前先核对生成时间、测试范围和相关文件是否随后变化。

## 下一步接手顺序

1. 发布门禁：用户执行 Android/iOS 实机清单 `docs/validation/yamibox-v2-manual-checklist.md`。
2. 用户若授权真实写入，提供专用账号、开关、允许列表和专用目标后再串行验收。
3. 用户在 macOS 上构建 iOS；代理不能在 Linux 跑 Xcode。
4. 可选：Linux 只读补验见「当前节点」清单，操作手册 `docs/engineering/linux-debug-ui.md`。
5. 上述 Android/iOS 证据齐备后，再用 `build_release.sh --platform <android|ios>` 打正式产物。
6. 在此之前不要宣称 V2 完成，不要递增版本。

首个执行命令：等用户安装 `1.0.5+9` 验证包并回传 Android 清单结果。

## 节点更新格式

每次更新本文至少改动：

- “最后同步”和“当前节点”；
- 本节点完成内容及对应文件/接口；
- 实际执行的测试、静态检查和构建日志；
- 尚未验证或明确禁用的边界；
- 下一节点、可安全修改范围和首个执行命令。

不要用“测试通过”替代平台或真实路径结论，也不要保留已经失效的日志、行号、并行所有权或下一步。
