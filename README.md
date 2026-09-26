<div align="center">

# Zemote

**ZCode Web 的多设备移动客户端** — 把多台电脑上的 `zcode --web` 链接加进来，在手机 / 平板上同时驱动它们的任务与对话。

[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue.svg?logo=flutter)](https://flutter.dev)
[![CI](https://github.com/HumanAILoop/zemote/actions/workflows/build-apk.yml/badge.svg)](https://github.com/HumanAILoop/zemote/actions/workflows/build-apk.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

</div>

---

## 它是什么

ZCode 的命令行发行包自带 Web 模式：`zcode --web` 会在电脑上启动一个 HTTP + WebSocket 服务，并打印一条带访问令牌的链接。ZCode 自己的 Web 界面是为桌面浏览器设计的，在手机上并不好用，而且一次只能打开一台电脑。

Zemote 做两件事：

1. **多设备**：保存任意多条 ZCode Web 链接，所有设备在后台同时保持连接，一键切换，列表里实时显示每台设备的在线状态、延迟以及正在运行 / 等待确认的任务数。
2. **按 ZCode 重做的移动端**：直接说 ZCode 自己的协议（`@zcode/rpc` 的 WebSocket Channel RPC + Conversation V4），界面沿用 ZCode 的设计系统（Zai Light / Zai Dark 语义色、`text-ui-*` 字号、圆角层级、「已工作 …」折叠、Composer 工具栏），手机上是 ZCode 移动端的单栏 + 抽屉布局，平板 / 桌面宽屏是侧栏 + 对话的分栏布局。

## 快速开始

在电脑上：

```bash
# 监听局域网；非本机地址会自动生成访问令牌
zcode --web --host 0.0.0.0 --workspace /path/to/project

# 建议固定令牌，否则每次重启都会生成新令牌、需要在手机上更新链接
zcode --web --host 0.0.0.0 --token "$(openssl rand -base64 24)"
```

终端会打印：

```
ZCode Web is running
Local:   http://127.0.0.1:3030/?token=…
Network: http://192.168.1.8:3030/?token=…
```

在 Zemote 里：**添加设备** → 粘贴 `Network` 链接（或扫描包含该链接的二维码）→ 保存。可以重复添加多台电脑。

> 旧版中继链接（`https://zcode.z.ai/remote/v4?sid=…&hash=…`）已不再支持。

## 功能

- **设备**：多设备并发在线、状态 / 延迟 / 活跃任务徽标、断线指数退避重连（1s → 15s）、回到前台时主动探活并立即重连、令牌失效时提示更新链接；链接在 Android 上以 Keystore AES-GCM 加密保存。
- **任务列表**（与 ZCode 侧栏一致）：tasks-index 决定持久成员（任务 / 置顶 / 已归档 / 已删除 / 未读），sessions-index 提供实时状态（运行中、等待确认、出错）；搜索、置顶、归档、删除。
- **对话**：Conversation V4 快照 + 增量实时同步，流式正文与思考过程、工具调用（命令、文件 diff、输出）、子代理、时间线标记；每轮按 ZCode 的方式分成用户消息、「已工作 …」折叠区与最终回答；向上滚动按需加载更早的消息；复制、重试、编辑用户消息、点赞 / 点踩。
- **交互**：权限请求（允许 / 始终允许 / 拒绝 + 反馈）、AskUserQuestion 多题问答（含自动结束暂停）、普通输入请求，回答格式与 ZCode 完全一致。
- **Composer**：新建任务（`createSession` + 首条消息）、后续消息、运行中排队、暂停队列时的「清空 / 保留队列」选择、停止、模式（变更前确认 / 自动编辑 / 计划模式 / 完全访问）、模型与思考档位切换、队列管理、后台任务。
- **其他**：中英双语、浅色 / 深色 / 跟随系统、字体大小、连接日志。

## 架构

```
lib/
├── core/                         与 UI 无关、可单测
│   ├── rpc/                      @zcode/rpc 的 Dart 移植
│   │   ├── serialization.dart    值编解码（tag + VQL，JSON 回退，嵌套字节标记）
│   │   ├── socket_protocol.dart  13 字节帧头的 SocketProtocol 分帧
│   │   └── channel_client.dart   ChannelClient：call / listen / cancel / dispose
│   ├── connection/               WebSocket 连接（原生 10s ping 心跳）、重连、探活
│   ├── link/device_link.dart     `zcode --web` 链接解析（/api/server-info、/ws?token=）
│   ├── zcode/                    服务门面（zcode-agent / zcode-task / model-selection）
│   └── v4/                       Conversation V4
│       ├── wire_assembler.dart   物理帧 → 逻辑帧（分片、CRC32、序号去重、超时）
│       ├── topic_router.dart     按 topic 路由；ACK 前到达的初始帧先暂存
│       ├── synced_topic.dart     快照 / 增量水位、断档 resync、重连后带 base 续订
│       ├── sessions_index_store.dart
│       └── conversation_store.dart  apply.ts 的增量代数 + V4 命令信封
├── state/                        设备注册表、每设备会话、任务列表、模型目录
└── ui/                           按 ZCode 设计系统重做的界面
```

为什么更流畅：旧版经由云端中继并在应用层做分片确认；现在手机直接与电脑上的 ZCode Web 服务建立 WebSocket，走与 ZCode 浏览器端相同的 Channel RPC。流式增量按微任务合并为一次重绘，未变化的对话轮复用同一个 Widget 实例，只有正在输出的那一轮会重建。

## 开发

```bash
flutter pub get
flutter analyze
flutter test                       # 协议、存储、链接解析、分组、启动流程

# 端到端：对一台真实的 ZCode Web 服务运行（需要已配置模型）
ZEMOTE_TEST_LINK='http://127.0.0.1:3030/?token=…' flutter test test/live_server_test.dart

flutter run                        # Android
flutter build apk --split-per-abi
```

Web 构建可用于调试，但浏览器会拦截跨域的 `/api/server-info`（ZCode 服务不带 CORS 头），需要与 ZCode 服务同源部署。

## 安全提示

- 链接中的 `token` 等同于这台电脑上 ZCode 的完全访问权限，切勿分享。
- `zcode --web` 默认是明文 HTTP，只建议在可信局域网或 VPN（如 Tailscale）内使用；跨公网请放在 HTTPS 反向代理之后（Zemote 支持 `https://…/子路径/?token=…`）。

## License

[MIT](LICENSE)
