# Synca

跨端灵感同步系统 — 在 iPhone 上随时记录灵感和待办，实时同步到所有 Mac 端。

## AI 连接（1.0.5）

云端 MCP 与 Web `/ai` 接入页面已加入，支持外部 AI 对话式管理记录、分类和附件。授权、工具契约、兼容性及发布验收见 [MCP 接入说明](docs/MCP.md)。iOS/macOS 沿用现有同步协议，1.0.5 在 iPhone/Mac 的更多菜单提供“连接 AI”入口，共用 Web 说明页；以复制连接指令和 OAuth 登录授权为主流程。

## 跨端导航约定

- iOS、macOS、Web 的套餐/额度标记紧跟 Synca 标题，可点击查看套餐。
- 功能菜单固定顺序：账号 → 分类管理 → 连接 AI → 提交反馈 → 关于 Synca。新增或调整菜单时，一起检查 `ios/Synca/Shared/Views/MessageListView.swift` 与 `web/src/components/FunctionMenu.tsx`，保持内容、顺序和中英文命名一致。
- 退出登录放在账号面板；客户端账号面板不展示管理后台链接。
- 连接 AI 共用 `/ai` 页面；验收覆盖手机窄屏、长文本、键盘焦点和深浅色模式。

## 核心功能

- **文字/图片同步**：手机端快速输入文字或选择图片，所有设备实时同步
- **消息流形态**：最新消息在底部，类似聊天界面
- **清理机制**：已处理的消息标记为"已清理"（变灰），不删除
- **角标提示**：iOS 角标 + macOS Dock 角标显示未清理数量
- **Sign in with Apple**：唯一登录方式，零配置

## 附件中转策略

| 权益 | 免费 | 付费（订阅或永久购买） |
| --- | --- | --- |
| 图片上限 | 50 MB | 50 MB |
| 普通文件上限 | 不开放 | 200 MB |
| 图片和文件合计空间 | 200 MB | 2 GB |
| 附件保留 | 3 天 | 7 天 |

文字不随附件到期删除；免费账号沿用每日 20 条新增内容限制。附件从上传完成计时，下载不续期，升级或降级不修改已上传附件的到期时间。永久购买解锁功能，不提供永久附件存储。容量满时停止新上传；未到期附件不会被自动挤出。

服务端通过 `/me/access-status` 的 `storage` 返回额度与使用量。上传使用 `X-Upload-Size` 预占空间，并以该大小限制接收流；缺省时按单文件上限预占。`X-Upload-ID` 为一次逻辑上传的 UUID，重试必须复用，以免网络响应丢失后重复创建消息。相同账号最多 4 个上传预占，上传最长 15 分钟。所有媒体仅通过鉴权后的 `/api/media/:filename` 访问，到期返回 410；旧 `/uploads` 公共入口已关闭。

服务启动后每分钟清理一批最多 200 个到期附件，失败保留记录以便重试；消息及文件名保留。磁盘清理成功后释放过期附件空间。崩溃遗留的上传预占在 1 小时后清理。正常请求失败或取消会释放预占。

发布时需同时部署后端、客户端和代理配置：`scripts/deploy-release.sh all` 包含 210 MB 请求体上限、15 分钟超时及上传请求关闭代理缓冲的配置。不能只修改客户端限额。存储策略测试使用隔离数据库运行 `backend/tests/storage.test.ts`，覆盖真实 50 MB 图片、200 MB 文件、容量并发、到期和幂等重试。

## 技术架构

```
┌─────────────┐     ┌─────────────┐
│  iPhone App │     │   Mac App   │
│  (SwiftUI)  │     │  (SwiftUI)  │
└──────┬──────┘     └──────┬──────┘
       │                   │
       │   HTTPS (REST)    │
       └─────────┬─────────┘
                 │
    ┌────────────▼────────────┐
    │   Nginx (SSL终端)       │
    │   synca.haerth.cn:443   │
    └────────────┬────────────┘
                 │ proxy_pass
    ┌────────────▼────────────┐
    │   Node.js + Express     │
    │   port 3002 (PM2)       │
    ├─────────────────────────┤
    │   SQLite (Kysely ORM)   │    ┌────────────────┐
    │   /opt/synca/backend/   │───▶│ Apple APNs     │
    │   data/synca.sqlite     │    │ (静默推送触发   │
    └─────────────────────────┘    │  客户端同步)    │
                                   └────────────────┘
```

## 目录结构

```
synca/
├── backend/                        # 后端服务
│   ├── src/
│   │   ├── server.ts               # 入口：启动 Express + 运行迁移
│   │   ├── app.ts                  # API 路由定义 (~280行)
│   │   ├── auth.ts                 # Sign in with Apple 服务端验证
│   │   ├── apns.ts                 # APNs 推送 (http2 直连, JWT 鉴权)
│   │   ├── store.ts                # 数据访问层 (Kysely 查询)
│   │   ├── db.ts                   # SQLite 连接初始化
│   │   ├── db_types.ts             # 数据库表类型定义
│   │   ├── types.ts                # 共享类型
│   │   └── migrate.ts              # 数据库迁移脚本
│   ├── tests/
│   │   └── api.test.ts             # API 集成测试 (14 tests)
│   ├── deploy.sh                   # 安全部署脚本 (rsync + PM2)
│   ├── .env.example                # 环境变量模板
│   ├── package.json
│   ├── tsconfig.json
│   └── vitest.config.ts
│
├── ios/Synca/                      # iOS + macOS 客户端
│   ├── project.yml                 # XcodeGen 项目配置 (双 target)
│   │
│   ├── Shared/                     # ★ 跨平台共享代码 (iOS + macOS)
│   │   ├── App/
│   │   │   └── SyncaApp.swift      # @main 入口, 条件 delegate adaptor
│   │   ├── Core/
│   │   │   ├── APIClient.swift     # HTTP 客户端, 所有 API 端点
│   │   │   ├── AuthService.swift   # Sign in with Apple 客户端
│   │   │   ├── KeychainHelper.swift# Keychain token 存储
│   │   │   └── SyncManager.swift   # 同步引擎 (轮询 + 增量同步)
│   │   ├── Models/
│   │   │   └── SyncaMessage.swift  # 数据模型 + API Response 类型
│   │   └── Views/
│   │       ├── LoginView.swift     # Sign in with Apple 登录页
│   │       ├── MessageListView.swift # 消息流主界面 + 输入栏
│   │       ├── MessageBubbleView.swift # 单条消息卡片
│   │       └── ImagePreviewView.swift  # 全屏图片预览
│   │
│   ├── iOS/                        # iOS 专属代码
│   │   ├── AppDelegate.swift       # APNs 注册 + 静默推送处理
│   │   ├── Synca.entitlements      # APNs + Sign in with Apple
│   │   └── Info.plist
│   │
│   ├── macOS/                      # macOS 专属代码
│   │   ├── MacAppDelegate.swift    # APNs + Dock 角标
│   │   ├── SyncaMac.entitlements   # 沙盒 + 网络 + 文件访问
│   │   └── Info.plist
│   │
│   └── Resources/
│       └── Assets.xcassets/        # 图标和颜色
│
└── README.md
```

## 后端 API

所有 API 均需 `Authorization: Bearer <token>` 头（除标注外）。

| 方法 | 路径 | 说明 |
|:----|:----|:----|
| GET | `/health` | 健康检查 (无需认证) |
| POST | `/auth/apple` | Sign in with Apple 登录 (无需认证) |
| GET | `/messages` | 消息列表，支持 `?since=ISO8601` 增量同步 |
| POST | `/messages` | 发送文字消息 |
| POST | `/messages/image` | 上传图片消息 (multipart) |
| PATCH | `/messages/:id/clear` | 清理单条消息 |
| POST | `/messages/clear-all` | 清理全部消息 |
| GET | `/messages/uncleared-count` | 未清理数量 (供角标使用) |
| POST | `/me/push-token` | 注册/更新推送 token |

### 数据库表

| 表名 | 用途 |
|:----|:----|
| `users` | 用户 (apple_user_id 关联 Apple ID) |
| `messages` | 消息 (type: text/image, is_cleared: 0/1) |
| `sessions` | 登录会话 (Bearer token → user_id) |
| `device_push_tokens` | 设备推送 token (支持多设备) |

### 同步机制

1. **发送消息时**：后端自动向该用户所有其它设备发送 APNs 静默推送 (`content-available: 1`)
2. **收到推送时**：客户端 AppDelegate 触发 `SyncManager.incrementalSync()`
3. **前台轮询**：App 在前台时每 5 秒增量同步 (`?since=最后更新时间戳`)
4. **App 回到前台**：监听 `willEnterForeground` / `didBecomeActive` 立即同步

### 增量同步原理

客户端记录上次同步的最大 `updated_at` 时间戳，请求 `GET /messages?since=<timestamp>` 获取增量变更。后端返回 `updated_at > since` 的所有消息（包括被清理的），客户端通过 `id` 匹配来更新或追加。

## 客户端跨平台策略

共享代码放在 `Shared/` 目录（同时被 iOS 和 macOS target 引用），平台差异通过编译条件处理：

```swift
#if os(iOS)
// UIKit APIs: UIDevice, UIPasteboard, UIImage
#elseif os(macOS)
// AppKit APIs: NSPasteboard, NSImage, NSWorkspace
#endif
```

主要平台差异点：

| 功能 | iOS | macOS |
|:----|:----|:----|
| 剪贴板 | `UIPasteboard.general` | `NSPasteboard.general` |
| 图片保存 | 保存到相册 | 保存到 Downloads |
| 角标 | `setBadgeCount()` | `NSApp.dockTile.badgeLabel` |
| 通知监听 | `willEnterForeground` | `didBecomeActive` |
| 图片压缩 | `UIImage.jpegData()` | `NSBitmapImageRep` |
| 键盘快捷键 | — | ⌘+Enter 发送, Esc 关闭 |
| 预览方式 | `fullScreenCover` | `sheet` |

## 服务器部署

### 资源分布 (与 everbond 完全隔离)

| 资源 | synca | everbond |
|:----|:----|:----|
| 代码目录 | `/opt/synca/backend` | `/opt/everbond/backend` |
| PM2 进程名 | `synca-api` | `everbond-api` |
| 端口 | 3002 | 3000 |
| nginx 配置 | `/etc/nginx/sites-enabled/synca-haerth-cn` | `/etc/nginx/sites-enabled/everbond-haerth-cn` |
| SSL 证书 | `/etc/letsencrypt/live/synca.haerth.cn/` | `/etc/letsencrypt/live/everbond.haerth.cn/` |
| 域名 | `synca.haerth.cn` | `everbond.haerth.cn` |
| 数据库 | `data/synca.sqlite` | `data/everbond.sqlite` |
| 图片存储 | `uploads/` | — |

### 环境变量 (.env)

```env
PORT=3002
APPLE_CLIENT_ID=org.haerth.synca
APP_STORE_APPLE_ID=6761647007    # 必须配置，否则线上内购收据验证会报错 invalid_purchase_transaction
APNS_ENABLED=true
APNS_KEY_ID=HCP7BQP4K5
APNS_TEAM_ID=7Y33M5HLSC
APNS_TOPIC=org.haerth.synca
APNS_AUTH_KEY_PATH=/opt/synca/backend/certs/AuthKey_HCP7BQP4K5.p8
```

APNs 是原有的后台同步功能。上面的 `.p8` 私钥需要单独安全配置到服务器，权限设为 `600`，不放入 Git 或发布包。后端部署会在切换服务前检查已启用推送的配置和私钥格式；更换密钥后需重启 `synca-api` 才会生效。

后台同步使用 `content-available` 和优先级 `5`，不携带通知声音、弹窗或角标；App 完成同步后自行更新角标。验证时应分别确认服务端配置、Apple 接口响应和真实设备同步，接口返回成功不代表设备已完成同步。

### 常用运维命令

```bash
# 同时部署 Web、后端和代理配置 (项目根目录执行)
bash scripts/deploy-release.sh all
# 单独部署仍可使用 backend/deploy.sh 或 web/deploy.sh

# 查看日志 (服务器)
pm2 logs synca-api --lines 50

# 重启
pm2 restart synca-api

# 查看状态
pm2 list

# 手动运行迁移
cd /opt/synca/backend && node dist/src/migrate.js
```

发布脚本先构建并上传到 `/opt/synca/releases/<时间>-<提交>/`，一致性备份 SQLite 和当前代码/代理配置，再执行增量迁移并切换版本。启动或代理检查失败会恢复旧代码和配置；不会用备份数据库覆盖上线期间的新数据。当前版本记录在 `/opt/synca/current-release`。发布后还需验证鉴权、真实上传、到期清理和多端同步，不能仅以健康检查作为验收依据。

### 运行测试

```bash
cd backend && npm test
cd ../web && ../backend/node_modules/.bin/vitest run --config vitest.config.ts
cd .. && bash ios/Tests/run.sh
bash ios/Tests/run-transfers.sh
```

后端覆盖存储边界、并发额度、清理重试、账号隔离、购买与 API 契约；Web 覆盖附件缓存/会话生命周期；原生覆盖列表索引、增量合并以及真实 200 MB 流式传输。原生传输脚本启动隔离本地测试服务，不使用线上账号。

## Apple 开发者配置

| 配置项 | 值 |
|:---|:---|
| Bundle ID | `org.haerth.synca` |
| Team ID | `7Y33M5HLSC` |
| APNs Key ID | `HCP7BQP4K5` |
| 需要的 Capabilities | Sign in with Apple, Push Notifications |
| 分发方式 | App Store (iOS + macOS) |

## 技术栈

| 层 | 技术 |
|:---|:---|
| 后端 | Node.js 22 + TypeScript + Express |
| 数据库 | SQLite + Kysely (类型安全 ORM) |
| 认证 | apple-signin-auth (验证 idToken) |
| 推送 | APNs (http2 直连, JWT, .p8 key) |
| 校验 | Zod |
| 测试 | Vitest + Supertest |
| 客户端 | SwiftUI (Swift 6, iOS 17+ / macOS 14+) |
| 项目管理 | XcodeGen |
| 部署 | rsync + PM2 + nginx + Let's Encrypt |
| 服务器 | 阿里云 ECS (123.56.247.129) |
