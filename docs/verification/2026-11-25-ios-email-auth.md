# iOS 邮箱登录与应用内双向绑定

## 已实现

- 登录页 Apple 优先，邮箱入口首屏显示。验证码通过即登录/自动创建账号；不增加注册确认或登录后绑定引导。
- 账号与套餐仍为两组，通过「登录方式」查看 Apple / 邮箱的绑定状态。Apple 用户可绑定邮箱，邮箱用户可绑定 Apple；冲突由已有后端拒绝，不合并账号。
- 邮箱、六位验证码使用系统键盘和自动填充；沿用桌面已确认的中、繁、英文文案。帮助用独立系统弹层，避免撑开表单。
- Apple 绑定传入服务端 nonce，并保持原会话；原生授权取消、迟到回调、返回、限流、过期、错误次数和重复提交均有处理。
- 邮箱登录复用 Apple 登录后的令牌、权益、APNs 注册和购买同步路径。购买同步新增跨会话保护；邮箱账号允许 Apple identity 为空。

## 设计与实现

类型：输入、身份管理、错误反馈、导航。参考系统 Settings 的二级账号列表与系统邮箱/验证码输入方式；保留现有登录品牌区和账号页分组。原生控件与语义字号、黑白主按钮、50 pt 最小高度、12 pt 圆角，内容可随键盘和大字滚动。错误提供文字、触感和 VoiceOver 提示，不把原始服务端响应暴露给用户。

依据：[Apple 账号管理 HIG](https://developer.apple.com/design/human-interface-guidelines/managing-accounts)、[Apple nonce 文档](https://developer.apple.com/documentation/authenticationservices/asauthorizationopenidrequest/nonce)。不新增后端流程或开放正式 Web 邮箱入口。

## 验证

- 单元/契约：11 项通过。结果 `/private/tmp/synca-email-final-unit-v2.xcresult`。
- 界面：3 条通过，覆盖邮箱错误码后重试成功、Apple 账号绑定邮箱、邮箱账号显示 Apple 绑定入口、帮助关闭前后输入框位置一致、浅深色截图。结果 `/private/tmp/synca-email-final-ui.xcresult`。
- 正式工程：仓库中 `Synca.xcodeproj` 的 Synca Production（arm64 simulator）和 SyncaMac Production 均 BUILD SUCCEEDED；不是仅测试自动生成工程。
- 三语言资源、项目格式、版本元数据及 `git diff --check` 通过。
- 复用 EverBond-TF-20261022 iPhone 17 / iOS 27；测试完已关闭。测试用独立应用标识与本机服务，未发送真实邮件，未访问正式用户记录。不是实际 Apple 授权/真实收信证明。
- 截图：`/Users/haer/Documents/Codex/2026-11-16/mini-synca-electron-1-2-0/ios-email-preview/`，`login-preview.png` 和 `binding-preview.png`。

## 真机验收

1. 登录首屏同时有 Apple 和邮箱，邮箱验证码登录后直接进入记录页，没有新增注册/绑定确认步骤。
2. Apple 登录后：设置 → 账号与套餐 → 登录方式 → 邮箱绑定；邮箱登录后同一路径可绑定 Apple。绑定前后记录和套餐归属不变。
3. 错码、过期、重发、返回/关闭可恢复；已归属其他账号的身份不能合并或抢占。
4. 真机实际收信、Apple 系统授权、钥匙串持久化、登录后同步与 APNs 仍需 TF 验收。本批仅本地保存，未触发 TF，未部署 Web/后端。
