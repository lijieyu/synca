# iOS / Electron TestFlight 发布修复

## 后台实证

- iOS Cloud 89（`1a731ee2-8f0d-49b4-8355-606ba79310f2`）对应 main `e5ed07b`，上传 1.1.1 (89) 被 ASC 90476 拒收：iPad 多任务开启，但 UILaunchStoryboardName 指向不存在的 LaunchScreen。
- 原生 project.yml 和已提交 pbxproj 仍是 1.1.1。编译成功不能验证上传要求。
- 同一个 Build for Release 工作流同时归档 Synca / SyncaMac，所以 Mac 88、89 是旧 SwiftUI 原生包，不是 Electron。Electron 最新可测试包仍为 1.2.0 (87)。
- Electron 工作流 `1f227670-c7fb-4d98-b988-611edb8c9db0` 原先仅手动启动旧分支 codex/electron-mas-preflight，且没有内测后续分发操作。

## 修复

- iOS 源配置与生成工程统一到 1.2.0；改为 iOS 14+ 支持的 UILaunchScreen 字典，保留 iPad 四方向与多任务。
- 添加元数据检查并接入原生 Xcode Cloud ci_post_clone，拒绝旧版本或丢失启动画面配置。可传入归档 app 路径检查实际产物。
- Electron 工作流改为 main 分支变化自动构建，保留 main 手动重试；维持指定稳定 Xcode/macOS、内部 TF 和正式后端。成功后仅分发给原有天使用户群（1 人）。
- Build for Release 删除 SyncaMac 归档及其内测后续操作，保留 iOS 自动构建与原内测群。未删除历史包、原生源码或本机 App。
- Cloud 构建号由 Apple 自动递增；本地 CURRENT_PROJECT_VERSION 不是云构建号，不手工重复触发。
- 正式 Web、邮箱开关、后端及法国分发未变。

## 验证

- 修复前复现：无 LaunchScreen.storyboard、无 UILaunchScreen，元数据断言失败。
- 真实通用 iOS Production 无签名 archive 成功，产物版本 1.2.0、UILaunchScreen 字典存在、iPad 四方向完整。
- `python3 ios/Tests/check-release-metadata.py /private/tmp/synca-tf-repair.xcarchive/Products/Applications/Synca.app` 通过。
- Electron build-info、出口声明、APNs entitlement 5 项测试通过。
- 前一轮 UI/同步行为未变，复用该版本已完成验证；本次仍须以新云构建成功与 TestFlight 内测状态作为可安装证据。
