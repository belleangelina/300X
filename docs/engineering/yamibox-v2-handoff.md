# 300X V2 开发交接状态

> 最后同步：2026-08-13，Cookie 属性安全桥、版块收藏、版块/收藏作者资料入口及横屏四入口详情保活代码子节点已完成，附件下载仍在进行。本文只记录脱敏工程状态，不保存账号、Cookie、`formhash`、帖子正文或私信内容。每完成一个可验证节点都必须更新本文；新会话应先读本文，再读 V2 规格和能力台账，并以当前工作树为最终事实。

## 当前目标与边界

- 工作分支：`feature/v2.0`，基于当前 V1 基线选择性实现 V2；禁止整体合并旧 `feature/full-forum`。
- 权威规格：`docs/spec/yamibox-v2.md`；逐能力状态：`docs/spec/yamibox-v2-capabilities.md`；用户实测：`docs/validation/yamibox-v2-manual-checklist.md`。
- 论坛结构、权限、动态字段和流程以真实移动网页为准，不使用电脑网页或旧分支扩大范围。
- 当前禁止任何自动真实站探针、业务 GET/POST、实机操作或截图。只允许本地实现、fixture/假服务自动化、静态检查和 Debug 构建；Android/iOS 实机由用户执行。
- 从本节点起禁止新建子代理。当前已经运行的版块收藏、附件下载和 Cookie 属性三个子任务可以完成；它们退出后，后续实现、集成与审查全部由主代理承担。
- 不可靠或未取得标准移动合同的写操作必须 fail closed，不得凭 URL、文案或桌面网页猜实现。
- 工作树是多人共享的大型未提交改动，不能覆盖、回退或格式化无关文件；修改前先检查 `git status`、近期文件时间和并行任务范围。

## 当前节点

目标是同时收口以下三条能力，再执行一次共享集成回归和 Debug 构建：

1. 版块收藏（已完成代码子节点）：添加入口是 GET 即突变，使用独立的请求前持久封存、单次 GET、完整收藏列表回读和人工解除；取消使用真实确认表单。真实写入和平台路径仍由用户验收。
2. 受保护附件下载：当前账号会话内严格同源下载、最终地址和身份校验、大小限制、临时文件原子落盘、取消/代际保护及系统打开。
3. WebView Cookie 属性安全桥（已完成代码子节点）：Android/iOS 原生桥在 App 与 WebView 间保留可证明的 Cookie 属性，并保持现有会话事务、WAF 锁序和身份切换安全；平台实机仍是发布门禁。

节点完成条件：三条实现各自定向测试和 analyze 通过；共享平台代码无冲突；受影响组合回归通过；Linux 与 Android Debug 构建通过；规格、能力台账、手测清单和本文同步。构建通过不代表实机通过。

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
- 论坛搜索已保留移动响应中的精确作者资料 URI，解析、缓存和点击前均绑定同一正 `uid`，搜索结果可进入原生个人资料。主题楼层、点评和评分作者的同类 URI 已进入领域模型、解析与缓存，Topic UI 点击接线需等待附件任务释放共享文件后完成。
- 版块主题列表已保留精确移动作者资料 URI，并在解析与离线缓存中绑定同一正 `uid`；可信入口显示独立作者按钮并进入原生资料页，漂移或恶意链接只保留作者文字。公告或没有资料合同的条目不显示空入口。
- 横屏主壳的左侧列表和右侧详情均按“漫画/小说、论坛、收藏、我的”四入口独立保活。切换主入口只改变可见索引，不销毁已打开的版块、主题、作品、异构收藏或个人二级页；隐藏详情停用 ticker，返回时不重复触发初始加载。
- 原始收藏中已经由 `FavoriteTargetContract` 严格识别的 `userSpace` 目标现接入原生个人资料页，窄屏使用完整路由、横屏使用收藏入口自己的保活右栏；URI 必须是同源 HTTPS、唯一正 `uid` 和 `mobile=2`，未知 `community` 类型仍保持不可执行。

上述“已完成”仅表示对应代码/自动化已存在；实际平台与真实业务写入状态必须以能力台账为准，不能概括为 V2 已完成。

## 当前并行修改所有权

- 版块收藏任务已完成并退出；`forum_board_favorite_repository.dart`、ForumBoardPage/RawFavoritesPage 对应入口和直接测试当前稳定，最终组合回归前只做主线审查修复。
- 论坛附件下载数据层、`forum_read_widgets.dart`、`forum_topic_page.dart` 及平台文件打开桥：附件任务正在修改。
- Cookie 属性任务已完成并退出；`forum_web_cookie_bridge.dart`、WebLogin/ForumOriginalPage 中的 Cookie 接线当前稳定。附件任务还会在 `MainActivity.kt`、`AppDelegate.swift` 追加独立文件打开通道，必须保留现有 Cookie 通道。
- 平台文件同时可能被文件选择、Cookie 和附件打开功能使用，必须基于最新内容做小范围追加，禁止整文件覆盖。

## 已知风险与明确未完成

- 2026-08-13 将两个版块收藏添加入口误当只读 GET，真实账号因此意外新增两条版块收藏。不得自动删除；用户需在移动网页“收藏 → 版块”按标题核对后逐条取消。不要再自动请求任一添加入口。
- 删除、投票、点评写入、评分写入和举报没有已验证标准移动合同，当前保持无原生可执行入口。
- 附件上传尚无完整 multipart、限制、结果和恢复合同；动态表单只识别文件字段并在 POST/封存前拒绝附件。Android 原页选择器代码存在不等于上传闭环。
- 普通回复、引用和编辑没有已验证成功响应合同；非明确失败必须保持 `resultUnknown`，只读回读不能自动判成功、删草稿或解除封存。
- 所有论坛业务 POST 均未在真实站验证；Android/iOS 全路径均未实机验证。
- iOS 在当前 Linux 环境不能执行 Xcode 构建；只能做 Dart/源码静态检查，最终由用户实机和 macOS 构建验收。
- Android 没有公开 API 可完整回读 WebView Cookie 的 Domain/Path/Secure/HttpOnly/Expires/SameSite；当前保守合并是安全边界而非平台已验证的属性完全等价，需用户实机验证登录、过期、登出、WAF 和切号。

## 最近可信证据

- 既有共享回归：论坛/社区 204 项、会话/认证/数据库 87 项、收藏/首页/作品 102 项曾通过；这些结果早于本节点三条新改动，节点完成前必须重跑受影响集合。
- 编辑组合测试 45 项及定向 analyze 已通过：`.artifacts/validation/logs/v2-edit-combined-tests.log`、`v2-edit-combined-analyze.log`。
- Android 文件选择器复核：`.artifacts/validation/logs/v2-android-file-selector-root-test.log`、`v2-android-file-selector-root-analyze.log`。
- Cookie 属性桥 18 项测试、analyze 和 Android Kotlin 编译：`.artifacts/validation/logs/v2-web-cookie-bridge-tests.log`、`v2-web-cookie-bridge-analyze.log`、`v2-web-cookie-android-kotlin-compile.log`。
- 版块收藏 focused 32 项与 analyze：`.artifacts/validation/logs/v2-board-favorite-focused-final-3.log`、`v2-board-favorite-analyze-final-4.log`；相关较早组合回归 34 项见 `v2-board-favorite-combined-tests-final.log`，本节点最终仍需纳入主线组合回归。
- 搜索作者原生资料路由 14 项及 analyze：`.artifacts/validation/logs/v2-forum-search-author-profile-tests.log`、`v2-forum-search-author-profile-analyze.log`；主题作者模型/缓存 18 项及 analyze：`v2-forum-author-profile-model-tests.log`、`v2-forum-author-profile-model-analyze.log`。
- 版块作者资料解析/缓存 14 项、版块 Widget 1 项及定向 analyze：`.artifacts/validation/logs/v2-board-author-data-tests.log`、`v2-board-author-widget-test.log`、`v2-board-author-profile-analyze.log`。同一文件中的完整主题页 Widget 集因附件任务中间态暂未作为组合证据，附件交付后重跑。
- 横屏详情保活先由 `.artifacts/validation/logs/v2-home-wide-detail-repro.log` 稳定复现重复版块请求，修复后直接用例及 HomeShell 全部 10 项通过：`v2-home-wide-detail-fixed.log`、`v2-home-wide-detail-regression.log`；定向 analyze：`v2-home-wide-detail-analyze.log`。
- 用户空间收藏解析/合同/列表 21 项及 HomeShell 路由 1 项通过：`.artifacts/validation/logs/v2-user-space-favorite-data-widget.log`、`v2-user-space-favorite-home-widget.log`；定向 analyze：`v2-user-space-favorite-analyze.log`。
- 版块收藏非典型合同证据：`.artifacts/validation/logs/v2-favorite-board-interaction-live-probe.log`。这是既有脱敏证据；禁止重跑真实站探针。

日志存在不等于覆盖当前工作树。使用前先核对生成时间、测试范围和相关文件是否随后变化。

## 下一步接手顺序

1. `git status --short --branch`，确认仍在 `feature/v2.0`，不要清理共享未提交文件。
2. 阅读三个状态文档和本文件；检查正在修改文件的最新时间，避免接管仍在运行的并行任务。
3. 等附件能力报告接口稳定、测试和剩余边界；逐条审查安全合同与跨文件接线。版块收藏与 Cookie 属性桥已退出并稳定。
4. 先跑各自直接测试，再跑受影响组合测试和定向 analyze；全部长输出写入 `.artifacts/validation/logs/`。
5. 最后执行 Linux/Android Debug 构建，不运行 Release 脚本、不递增版本；不做实机或真实站操作。
6. 根据最终事实更新规格、能力台账、手测清单和本文，再进入下一功能节点。

## 节点更新格式

每次更新本文至少改动：

- “最后同步”和“当前节点”；
- 本节点完成内容及对应文件/接口；
- 实际执行的测试、静态检查和构建日志；
- 尚未验证或明确禁用的边界；
- 下一节点、可安全修改范围和首个执行命令。

不要用“测试通过”替代平台或真实路径结论，也不要保留已经失效的日志、行号、并行所有权或下一步。
