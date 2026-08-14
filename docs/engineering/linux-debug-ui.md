# Linux Debug 按 Key 点击

Linux 不是产品平台。这份说明只给本机 Debug 实机用：对着**正在跑的 Debug 包**按 Flutter `Key` 点控件，不要再猜屏幕坐标。

Release / `kReleaseMode` 不会启动该入口。服务只绑 `127.0.0.1`。

## 何时用

- 共享原生只读路径要在 Linux 上点界面（版块、主题、本版搜索、资料、好友/访客等）。
- 不要用它替代 Android/iOS 清单，也不要用来点未授权写入、通知或私信正文。

解析、仓库合同仍应先走 fixture/单测。只有必须看到真实界面时才用这里。

## 启动

```bash
flutter build linux --debug
DISPLAY=:0 GDK_BACKEND=x11 build/linux/x64/debug/bundle/x300
```

日志里会出现：

```text
x300 debug ui: http://127.0.0.1:17830  (/tmp/x300-debug-ui.json)
```

Debug 引擎通常还会打印 Dart VM Service URI。日常实机用 HTTP；VM 扩展是同一套命令，不是主入口。

## 命令

端口以 `/tmp/x300-debug-ui.json` 为准。进程异常退出时该文件可能残留，先 `health` 再点。仓库脚本：

```bash
tool/debug_ui.sh health
tool/debug_ui.sh keys
tool/debug_ui.sh find key=forum-board-search
tool/debug_ui.sh wait key=forum-search-submit timeoutMs=15000
tool/debug_ui.sh tap key=home-tab-forum
tool/debug_ui.sh enter key=forum-search-keyword text=某个词
tool/debug_ui.sh back
```

也可直接：

```bash
curl -sS 'http://127.0.0.1:17830/tap?key=home-tab-forum'
```

返回都是 JSON。`ok: true` 才算点到。常见失败：

| error | 含义 |
| --- | --- |
| `not_found` | 当前树里没有这个 Key |
| `offstage` | Key 在隐藏页（例如未选中的主入口） |
| `disabled` | 按钮 `onPressed` 为空 |
| `not_hittable` | 有 Key 但中心点被挡住或未滚进视口 |
| `not_editable` | `enter` 找不到输入框 |
| `timeout` | `wait` 到期仍未出现 |

`tap` 若目标在可滚动区域但未命中，会先 `ensureVisible` 再点一次。被 FAB 或其他叠层挡住时会拒绝，避免点到旁边的写入按钮。

## 稳定 Key

| Key | 控件 |
| --- | --- |
| `home-tab-library` / `home-tab-forum` / `home-tab-favorites` / `home-tab-profile` | 四主入口 |
| `forum-home-search` | 论坛首页搜索 |
| `forum-community-menu` | 社区菜单 |
| `forum-community-profile` | 菜单里的个人资料 |
| `forum-board-{fid}` | 首页版块 |
| `forum-board-search` | 本版搜索 |
| `forum-thread-{tid}` / `forum-announcement-{id}` | 版块列表条目 |
| `forum-search-keyword` / `forum-search-submit` | 搜索框和提交 |
| `forum-topic-prev` / `forum-topic-next` | 主题分页 |
| `community-profile-entry-{kind}` | 资料页入口，`kind` 如 `friends`、`favorites` |
| `community-people-tab-{kind}` | 好友/在线/访客/足迹页签 |

`keys` 也会列出封面 `file://` 路径、部分整型 `ValueKey`，不要拿来点。

未授权时不要点：

- `forum-new-thread`、`forum-reply-thread`、`forum-favorite-*`、`forum-action-submit`
- `forum-community-notices`、`forum-community-messages`、`community-profile-entry-messages`

## VM 扩展

Debug 进程会注册 `ext.x300.debug.ui`。参数与 HTTP 相同：`cmd=health|keys|find|wait|tap|enter|back`，另加 `key` / `text` / `timeoutMs`。

Linux Debug 二进制常会自己打开 VM Service，但带鉴权 path，URI 每次启动都变。实机脚本继续用 HTTP。

## 已知边界

- 只在 `kDebugMode` 安装。不要把调用放到正式包。
- 没有 Key 的控件仍然点不到；缺 Key 就补 Key，不要退回 xdotool。
- `enter` 只改本地输入框。搜索提交仍是一次只读 GET，未授权不要点 `forum-search-submit`。
- Widget 测试里 Flutter 会拦截真实 HTTP，自动化测 `DebugUiAutomation.tap` / `dispatch`，HTTP 以本机 Debug 包为准。
