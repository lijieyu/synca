# Synca Electron 1.2.0

本地打包共享 React 前端，沿用 Synca 服务、Apple 登录来源和既有桌面用户配置。Mac Bundle ID 为 cn.haerth.synca.electron。正式签名 APNs 需要独立的 App ID、推送权限、匹配的 provisioning profile 和签名。当前交付的 Mac ZIP 使用 ad-hoc 签名，Windows ZIP 为未签名的 x64 便携包。

## 构建

在 Mac 上使用 Node 25、npm 和 codesign。先运行 npm ci --ignore-scripts。将 SYNCA_WEB 指向 Synca 仓库的 web 目录，在该目录执行 npm ci，或通过 SYNCA_WEB_MODULES 指向另一份按相同锁文件安装的 node_modules。

在 Mini 上单独构建 macOS arm64 使用 `npm run build:mac`。

npm run build 会先执行 node build-ui.mjs，在临时目录将 frontend.patch 和 ui 合入共享前端、类型检查、编译并生成 app/renderer。设置与 Markdown 直接使用同仓库 web/src/components 下的共享实现。补丁基线不兼容会令构建失败。之后自动生成安装包。可设置 ELECTRON_ZIP_DIR 使用本地运行时（校验 npm 官方哈希），并设置 SYNCA_BUILD_DIR 指定输出路径。推荐使用本机临时构建目录以避免云盘为 app 增加 FinderInfo 属性。

## 实现位置

web/src/components/SettingsPanel.tsx 与配套 CSS 统一管理 Web 和 Electron 的设置导航、焦点及宽窄布局。账户和关于复用共享前端内容。app/platform.cjs 管理本机设置、下载、角标、APNs 和 Windows 托盘。app/preload.cjs 提供最小桌面接口。ui/snapshot.ts 管理登录会话隔离的历史缓存及输入草稿。app/local-ui.cjs 从安装包提供界面资源，其余请求交由网络服务。

## 验收

设置 SYNCA_BACKEND 指向已编译且依赖完整的本地 Synca backend，执行 node verify.mjs "/path/to/Synca Electron.app/Contents/MacOS/Synca Electron"。CAPTURE_DIR 可指定现有的截图输出目录。该脚本使用临时账户与 SQLite，验证桌面设置、草稿、中文输入、编辑、搜索、同步、离线读取和角标并采样进程。node popup-check.mjs 可检查 Apple 授权窗口。Windows 托盘和推送签名需在对应环境单独验收。

## 隔离预览（macOS arm64）

- `npm run build:mac:preview` 生成独立身份和数据目录的远程预览包，仅允许 `https://synca-preview.haerth.cn`；不会回退正式站、启动 Apple 登录或注册 APNs。预览站的访问门禁由预览运维负责，不能在包里放口令。
- `npm run build:mac:local-preview` 生成独立的本机体验包，仅转发到 `127.0.0.1:30642` 的合成测试夹具。不会发真实邮件、登录 Apple 或连接正式数据。夹具独立启动，需验证局部健康标记和主进程从专用数据目录读取的 0600 临时访问文件；这个文件既不打包也不交给渲染进程。客户端没有用于访问网站或生产的回退代码。
- 改用新的测试配置前退出现有预览包；正式 Electron 与原生 App 不用退出、不用替换。
