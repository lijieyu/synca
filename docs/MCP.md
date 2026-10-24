# Synca 1.0.5 — 云端 MCP

## 范围

后端提供标准 Streamable HTTP MCP (`POST /mcp`)、同源集成 API (`POST /api/ai/tools/:toolName`) 和 OAuth 授权。Web `/ai` 提供公开说明、授权、撤销与操作记录。iOS/macOS 的更多菜单新增“连接 AI”链接，共用 `/ai` 说明页，1.0.5 更新版本元数据，保留正在审核的 1.0.4 Build 31；继续使用现有增量同步、分类和 APNs 接口。

## 接入

公开地址为 `https://synca.haerth.cn/mcp`。部署前配置 `PUBLIC_URL=https://synca.haerth.cn`，必须与用户访问 Web 的 origin 一致，不能从请求 Host 推导授权地址。

- OAuth：发现 `/.well-known/oauth-protected-resource/mcp` 和 `/.well-known/oauth-authorization-server`。支持公开客户端动态注册、授权码、S256 PKCE、精确匹配 redirect URI、resource 绑定和单次授权码交换。授权码有效 60 秒、授权页面请求有效 10 分钟。
- 新 OAuth 授权最长 365 天。申请 `refresh_token` 的客户端获发 1 小时 access token 与一次性轮换 refresh token；刷新令牌连续 180 天未使用失效，每次刷新最多延续至原授权到期日。检测到旧刷新令牌重放会撤销整条连接。Web 撤销立即阻止访问和刷新。
- 只申请授权码的客户端仍使用 30 天 access token，无自动续期。旧连接保持原有效期；启用续期需要重新注册并授权（旧客户端注册记录未获准 refresh grant 时，通常需要删除后重新添加 MCP）。
- `/ai` 不再提供手动配置和个人访问令牌入口，统一引导用户通过 AI 应用配置 MCP 并完成 OAuth 授权。后端个人令牌接口与已有连接保持兼容。
- 不将令牌放进 URL、提示词、聊天记录或版本库；Apple 登录会话不能用于 MCP，AI 令牌也不能用于账号、支付、反馈或管理员 API。
- 已实现通用协议并通过官方 SDK 客户端联调，不代表所有第三方产品及其手机版本均开放自定义 MCP。上线后逐一验证目标客户端。动态注册支持 `none`、`client_secret_post`、`client_secret_basic`；密钥只保存 SHA-256 摘要，换取令牌时严格匹配注册的认证方式，仍要求 S256 PKCE。客户端可同时申请 `authorization_code` 和 `refresh_token`；刷新绑定原客户端、原资源和授权权限，仅可缩小权限。不支持远程客户端元数据 URL 解析。

## 工具与权限

| 工具 | 功能 | 权限 |
| --- | --- | --- |
| `search_records` | 关键词、分类、日期、状态筛选，游标分页，最多 100 条/页 | read |
| `read_record` | 记录详情、版本及附件元信息 | read |
| `create_record` | 新增最多 2000 字符文字，UUID 幂等键 | create |
| `update_records` | 单条文字编辑、批量分类和完成/恢复状态，最多 100 条 | update |
| `list_categories` | 分类和版本 | read |
| `manage_category` | 新建、改名、改色、排序、删除分类；删除分类将记录移入默认分类 | 按操作 create/update/delete |
| `prepare_delete_records` | 指定记录或已处理记录的删除预览，最多 500 条 | delete |
| `delete_records` | 用户在对话中二次确认后，执行预览中的准确记录；参数 operationId、confirmed: true | delete |
| `get_operation` | 查询本连接发起的操作结果 | 有效连接 |
| `get_usage` | 用量、容量、保留期、未处理数量 | read |
| `create_attachment` | 对话内上传最多 5 MiB 的 base64 图片/文件 | create + attachments |
| `read_attachment` | 对话内读取最多 5 MiB 附件，返回 image 或 embedded resource | read + attachments |
| `attachment_transfer` | 大附件鉴权 HTTP 传输说明；不抓取任意外部 URL | attachments + create/read |

大文件继续使用 `POST /messages/image` 或 `/messages/file`，需要 `X-Upload-ID`（逻辑上传的稳定 UUID）、`X-Upload-Size` 和 Bearer token；multipart 文件字段为 `image`/`file`。下载使用受保护的 `/api/media/:filename`。客户端若只能调用 MCP、不能进行 HTTP 文件传输，应使用小附件工具或说明此限制，不能声称已完成大文件传输。

所有附件沿用现有类型白名单、每日新增额度、空间限制、付费文件权限、3/7 天保留期和清理重试。正文与附件不永久存入 MCP 服务的额外知识库。过期附件返回明确错误，不推断或虚构其内容。

## 写入与删除约定

- 文字/小附件/分类创建使用 `idempotencyKey`，同一连接同一键的不同请求返回冲突。
- 编辑记录携带每条当前 `expectedUpdatedAt`；一批中任意记录冲突、归属不符或不存在，整批回滚。
- 分类更新和删除携带版本；排序提供所有非默认分类的 categoryIds 和 categoryVersions（id、expectedUpdatedAt）。默认分类不可修改或删除。
- `prepare_delete_records` 只创建待确认操作，返回 operationId、数量、记录摘要、expiresAt；不返回网页链接。AI 说明删除范围、数量及不可撤销性，等待用户在对话中单独二次确认后，再调用 `delete_records({ operationId, confirmed: true })`。初次删除请求和记录正文均不代表确认。批量清理可概括范围和数量。
- 服务端验证确认参数、预览归属和有效期，但无法证明 AI 是否真实征得用户同意；对话确认由接入 AI 遵循工具描述执行。取消时不执行删除。网页删除确认 UI 与 `/api/ai/confirmations/:id` 接口已移除；OAuth 登录授权页继续保留。
- 新工具上线后，AI 客户端需要刷新工具列表或重新连接；权限未变化，无需新增授权范围。
- 确认绑定账号、连接、准确的记录列表、版本和 10 分钟期限。执行时重新校验连接及记录版本，拒绝其他连接执行。确认后的新增记录不会被纳入。
- 删除不能撤销；取消、过期、撤销连接、版本冲突都不会删除记录。删除后发送原有 tombstone，附件由现有清理器处理。
- 操作日志记录连接与动作。文字创建的幂等校验保存请求摘要，文字编辑日志不保存正文；到期删除预览会清理片段。账号删除会清理授权与日志。
- 修改通过现有数据库模型和时间戳同步至 Web/iOS/macOS，成功提交后触发原有 APNs 通知。服务端接受推送不等于真机已收到。

## 部署

只需发布 Web、后端和代理配置，使用现有 `scripts/deploy-release.sh all`。脚本新增 `/mcp`、`/oauth/` 和 OAuth discovery 路由；MCP 关闭代理缓冲。`/api/ai/*` 使用独立前缀代理，保留完整路径。发布前检查真实 nginx 配置及 TLS，避免落入 SPA fallback。

迁移只新增 `ai_connections`、`ai_operations`、`ai_oauth_clients`、`ai_oauth_requests` 及索引，不重写消息表。旧后端回滚可忽略新增表，不要恢复旧数据库覆盖新记录。

本批开发不等于发布，不自动提交 App Store，不以本地测试代表线上或第三方客户端已验收。

## 验证

```sh
cd backend
npm run build
npm test
# 单独跑 MCP，必须指定隔离测试数据库
DB_PATH=synca.ai.test.sqlite ./node_modules/.bin/vitest run tests/ai.test.ts
cd ../web
npm run build
../backend/node_modules/.bin/vitest run --config vitest.config.ts
cd ..
bash ios/Tests/run.sh
bash -n scripts/deploy-release.sh
```

MCP 测试覆盖官方 SDK 的实际 HTTP 握手/发现/工具调用、读写权限、跨账号隔离、管理员附件隔离、幂等键、免费额度、搜索转义/分页、冲突回滚、旧客户端增量契约、小附件读写和到期、用户确认删除、OAuth PKCE/重放/resource/redirect 校验。

上线验收：真实登录创建或授权连接 → 外部 AI 搜索/新增/编辑/分类 → 三端检查内容及未处理数 → 撤销后拒绝访问 → 删除预览与对话二次确认 → 检查旧 1.0.4 真机同步。必须分别确认 iPhone、Mac 和 Web，不能仅检查 HTTP 200。

## 本批本地验证（2026-10-24）

- 后端构建通过；75 项回归通过，其中 16 项 AI/MCP 集成测试。
- Web 生产构建通过；14 项现有回归通过，新页面 ESLint 通过。
- 原生共享测试通过：时间戳、会话隔离、增量合并、编辑/删除/计数及 10,000 条记录索引。
- 浏览器验证中文/英文公开页、390px 手机宽度、测试账号令牌创建/隐藏/撤销。
- 生产依赖 `npm audit --omit=dev` 为 0 告警。修复了已有 multer、Kysely、UUID、Zod、请求解析及 form-data 相关依赖；Zod 迁移到 4.x 已通过完整后端回归。开发测试工具链仍有历史审计告警，不将生产审计结果描述为全仓零告警。
- 按授权的 TF 流程发布 1.0.5；第三方 AI 产品及真实设备验收须在部署后执行，既有 1.0.4 Build 31 审核包保持不变。

## 连接体验

主流程为复制连接指令 → AI 添加/连接远程 MCP → OAuth 登录确认 → 返回对话验证。无需在说明页先登录或创建令牌。客户端在更多菜单通过系统浏览器打开共享说明页，并传递中英文偏好。页面不展示高级手动配置或个人令牌表单。提示词不含任何凭证，也不保证 AI 应用拥有自动安装能力；不支持自动安装时，由 AI 提供当前应用的必要步骤。

### 授权与用量验收

授权详情和批准接口必须使用用户登录 session；MCP token 不能批准授权。所有工具按 token 所属 user_id 隔离，操作结果还限定 connection_id。`get_usage.access.todayLimit=null` 且 `isUnlimited=true` 表示无每日记录上限；`unclearedCount` 只是尚未完成且未删除的记录数，不是剩余额度。无限版仍有附件容量及保留期限。

刷新回归覆盖无登录批准、访问令牌过期、三种客户端认证、跨客户端刷新、错误资源、权限扩大、轮换重放、并发重放、180 天闲置和365天硬截止、撤销及重复迁移；旧连接不自动延长。
