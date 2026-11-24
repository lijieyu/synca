# 关于页版本标识 — 2026-11-24

- 客户端显示 `macOS · 1.2.0 (87)` / `Windows · 1.2.0 (87)` 这种格式，build 来自包内构建信息，不是页面常量。
- 普通桌面打包从 Xcode 发布配置读取版本和 build，并校验 app/package.json 主版本一致；写入签名前的 Resources/build-info.json。Windows 可执行文件版本同步为主版本加 build。
- MAS 归档在签名前重新读取最终 Xcode 处理后的 Info.plist，将实际 CFBundleShortVersionString / CFBundleVersion 写入资源。不会把准备包的旧 build 当作最终归档号。
- 主进程读取资源，通过受限 preload 传给前端。未打包开发启动无 build 时只显示版本，不虚构一个编号。
- Web 显示 `网页版 · YYYY.MM.DD · 短提交号`，日期按北京时间生成，版本号独立于 TF。发布构建没有源码提交标识时明确失败；Electron 暂存前端构建显式传入原源码位置。

验证：19 项桌面测试通过，包括包信息读取、preload、二进制 plist 最终归档号覆盖旧准备号，以及现有 Windows/Mac 兼容约束。Web、Mac、Windows 三种关于页在 640×500 布局下通过，版本行无横向溢出。Web 和 Electron 共用前端生产构建通过。浏览器测试使用模拟桌面桥接；未打包新 TF / Windows 安装包，客户端显示随下次发包生效。
