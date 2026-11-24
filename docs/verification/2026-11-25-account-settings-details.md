# 账号与设置细节修复 · 2026-11-25

## 范围
- iOS 邮箱登录的自动创建说明和协议合并为一个本地化段落；原有条款/隐私 URL 分别保留为可访问链接。
- 账号身份移到分组上方，登录方式一行、套餐和附件用量合并一行；账号操作仍独立，删除仍需确认。
- 已绑定邮箱与名称同行；长地址中间省略，保留完整值供复制和朗读。
- iOS/原生 Mac 的退出与删除确认由账号页承载，取消和失败不关闭设置；删除中禁止重复提交和返回。
- Web/Electron 全宽分类添加入口恢复 44px，其他普通操作按钮的 36px 规格保持。
- Web/原生反馈和关于共用官方 512px 小红书图标，替换原 32px 图。

## 图标来源
小红书 App Store 公开素材，App ID 741292507。
- 商店：https://apps.apple.com/cn/app/id741292507
- 元数据：https://itunes.apple.com/lookup?id=741292507&country=cn
- 原图：https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/69/c3/c8/69c3c8f3-5b08-09fc-2f8b-a9fe28d47063/AppIcon-0-0-1x_U007epad-0-11-0-85-220.png/512x512bb.jpg
本地图片为同一份 512×512 JPG，没有放大原 32px 图、重新描画或修改品牌标识。

## 验证
- 修复前：隔离 iPhone 复现退出确认取消后账号页消失，新增回归用例失败。
- 修复后：退出取消、删除取消、删除失败保留账号页通过；本机假服务不会发送邮件或删除真实账号。
- Web 定向浏览器检查通过：分类添加高度至少 44px、图标原始尺寸、退出取消保留设置；浅深色截图。
- 5 条 iPhone UI 用例通过：原地确认、邮箱绑定、邮箱账号绑定入口、错误验证码后成功登录、设置页面完整走查。
- 额外 2 条检查通过：确认退出回到登录页、最大辅助字号账号排版及英文协议段落。
- 最终邮箱行定向复测通过：绑定后“邮箱”标题实际可见，标题与地址中线误差不超过 2pt；固定系统 Label 为图文样式，避免自动隐藏标题。
- Web 构建、原生 Mac 构建、三种语言字符串校验通过。
- 类似流程审计：分类删除确认、反馈放弃编辑、现代 Web 账号确认均原地处理；AI 页面在会话失效时关闭属正常行为。

## 发布范围
本批仅本地实现和验证，未部署 Web、未提交 TF。正式 Web 邮箱入口开关未改。

## 验证边界与证据
- 测试服务只监听 127.0.0.1；未发送真实验证码、未撤销授权或删除真实账号。
- 真实邮件送达、Apple 授权、成功删除账号以及 VoiceOver 实机朗读未在这次真实账号上执行。删除取消/失败和确认退出已经隔离验证。
- 主要日志：`/private/tmp/synca-account-detail-after.log`、`/private/tmp/synca-account-detail-extra.log`、`/private/tmp/synca-account-detail-binding-v2.log`、`/private/tmp/synca-account-detail-web-build.log`、`/private/tmp/synca-account-detail-mac-build.log`。
- 截图：`/Users/haer/Documents/Codex/2026-11-16/mini-synca-electron-1-2-0/account-settings-detail-preview/`。
