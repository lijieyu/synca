# Synca 1.2.0 商店草稿检查表

核对日期：2026-11-25。本文件只记录本地上架准备，不代表 App Store Connect 保存、提交或发布。主会话负责最终后台状态与构建选择；本轮未操作后台、未运行模拟器、未更新地区或价格。

## 可直接使用的字段

完整三语公开文本与英文审核说明：`2026-11-25-store-copy-draft.md`。逐字段粘贴来源：`2026-11-25-store-metadata.json`。名称/副标题采用既有 ASO 候选 A，保持口号用于图片和宣传文本。

| 语言 | 名称 | 副标题 | 名称/副标题/关键词字符数 |
| --- | --- | --- | --- |
| 简中 | Synca · 笔记与文件传输 | 文字图片随手记，手机电脑多端同步 | 15 / 16 / 69 |
| 繁中 | Synca · 筆記與檔案傳輸 | 文字圖片隨手記，手機電腦跨裝置同步 | 15 / 17 / 65 |
| 英文 | Synca: Notes & File Transfer | Quick capture, sync everywhere | 28 / 30 / 90 |

名称与副标题属于跨平台 App Information；描述、宣传文本、关键词和更新内容须分别保存到 iOS/macOS 版本的对应语言。JSON 中 iOS/macOS 更新内容已分开，不能整份复制到同一字段。搜索相关性是建议依据，没有搜索量或排名提升保证。

Apple 现行限制：名称/副标题各 30 字符、宣传文本 170、描述和更新内容各 4000。关键词产品页指南写 100 字符，字段参考写 100 bytes；此前主会话 ASC 实测支持该应用的 100 字符。原候选简中/繁中为 161/151 bytes，需以保存回读为准；JSON 同时提供各 35 字符/79 bytes 的保守备用串，只有实际字段拒绝时才切换，避免擅自削减已拟定覆盖。审核 Notes 为 4000 bytes，凭据须放专用审核字段，禁止混入公开文本。

## 版本与能力证据

| 项目 | 本地已核对 | 尚需最终回读 |
| --- | --- | --- |
| App | Apple ID 6761647007；目标营销版本 1.2.0 | 对应 iOS/macOS 1.2.0 草稿记录与可编辑状态 |
| iOS | `ios/Synca/project.yml` 与已提交工程版本 1.2.0；本地 build 1 | Cloud 自动递增构建号、最终提交、可供审核的构建 |
| macOS | Electron 工程 1.2.0、本地 build 87；`desktop/release-version.mjs` 从归档工程读取版本 | 必须选择新 Electron 正式构建；不能按较大 build 号误选旧 SyncaMac SwiftUI 包；内部专用 TF 包不等于公开送审包 |
| 新增登录 | iOS 本地契约/界面测试和正式工程编译；Mac 历史正式邮箱收信与记录回读 | 最终包实际 Apple 授权、邮箱收信、两个绑定方向、登录后同账号记录与购买归属 |
| Web / Windows | `2026-11-25-launch-web-release.md` 有公开入口与完整下载哈希证据 | 本轮如替换官网版本，使用新部署回读覆盖旧证据；x64 硬件运行未验证 |
| Pro / 存储 | 源码：免费 20 条/天、100 MB、3 天；Pro 不限新增条数、1 GB、30 天；普通文件与 MCP 为 Pro | 最终服务权益与购买流程；终身权益不代表永久附件保存 |

本地审核基线为 `15ed2319fc7b01c1990c5b5a24e11ea828c8535e` 加当前已验证搜索/外观/首屏修复。未把本地 build 1/87 写成最新 TF 或公开版构建号。更新内容只追加已有验收的外观跟随系统、短列表首屏与搜索横向滚动修复。

## 头图与现有截图

- **头图 v3**：用户已接受保留原设备与 slogan、移除 logo 和淡紫装饰线。两个 v3 manifest 已同步此状态，图像未改。文件为 3840×1646 RGB PNG；Apple 安全区为 x1097/y493、1646×661。当前布局并未把全部关键内容放在中央安全区，因此仍需实际 ASC 裁切预览，整体素材状态保留 `draft`。不能因为用户接受视觉方向就宣称跨设备裁切通过。
- **头图 UI 来源**：保留既有 ASC 素材中的设备画面，未重拍 1.2.0。该头图不是第一张 App Store 截图，也不能充当最新构建截图证据。仅简中版本，不将简中文字图直接覆盖繁中或英文槽位。
- **既有截图组**：`docs/website/README.md` 记录 `release-1.1.0-five` 共 45 张，即三平台×三语言×五场景。它们源自 1.1.0 实拍/已披露的局部合成，不能直接认定为当前 1.2.0 合格截图；本轮未取得后台逐槽位文件清单，也未逐张复核。
- **刷新判断**：Mac 主窗口已从旧 SwiftUI 转为 Electron，应刷新实际展示旧 Mac 界面的截图内容；iPhone/iPad 涉及侧栏、设置、分类、外观的画面需与 1.2.0 逐张比对，仅更新确有不一致的画面。既有构图、顺序和五场景方案可保留，不因版本更新自动重做全部海报。AI 场景若仍真实准确可复用已获准素材，但不能把入口截图称为连接成功。
- **当前可用验收图**：iOS 邮箱、11 月 24 日 iPhone/iPad 界面、11 月 25 日外观/短列表、Mac 设置和搜索均有定向验收目录。它们不是完整三语商店尺寸导出组；部分桌面设置图含私人账号信息，禁止直接上传。需要更新时使用已批准的虚构演示内容与独立拍摄来源。

## 明早逐项检查

1. **草稿回读**：App 6761647007、iOS/macOS 1.2.0、三个本地化；名称/副标题及各平台文本与 JSON 对齐，无旧 SYNCA99/9.9 文案，无误覆盖其他语言。记录实际保存状态。
2. **截图和头图**：逐平台、语言核对现有数量与顺序；保留原方案，仅标明需要更新的旧 UI。v3 实际裁切预览通过后再升为可上传状态；尚未通过就保留待处理，不提交资产审核。
3. **审核可进入**：最终包实际登录、购买与 Pro 测试路线可用；提供经授权且不失效的审核访问方案。开发者本人收一次验证码不能单独替代审核员可用的凭据。
4. **链接和字段**：营销链接分别 `/home/`、`/home/zh-Hant/`、`/home/en/`。后端法律路由仅 `en|zh-hans`，繁中隐私链接已修正为现有 `/zh-hans/privacy-policy`（页面简中）；支持 URL 同理。最终检查实时页面确实可打开、支持页有真实联系方法。版权、审核联系人沿用后台真实值，不凭空填写。
5. **合规与发布策略**：按最终构建核对加密声明、隐私、年龄评级与现有发布选项。保留法国和当前分发地区；本地材料不授权提交 ANSSI、代签或改变法国分发。内测问卷与公开分发证据分别记录。
6. **停在可审阅草稿**：本轮目标是完成 TF 流程与上架准备，提交 App Review、正式发布及资产审核状态分别报告；草稿保存、上传成功或 TF 构建成功都不等于已上架。

## 本轮核验来源

- [Apple 产品页指南](https://developer.apple.com/app-store/product-page/)；[App Information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)；[版本字段参考](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)，2026-11-25 打开核对。
- [截图规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)；[创意素材规格](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications/)，2026-11-25 打开核对。此次未生成或上传截图，实际槽位须以后台回读为准。
- `backend/src/storagePolicy.ts`、`backend/src/usagePolicy.ts`、`backend/src/access.ts`、`backend/src/app.ts`、`backend/src/legalPages.ts`、两个原生/桌面归档工程与已有验收记录。
- 本轮公众支持页面网络读取未完成；只核对了源码路由和官网现用链接，不把该读取超时报告成页面故障或链接上线成功。
