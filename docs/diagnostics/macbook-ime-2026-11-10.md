# MacBook 五笔输入抖动：根因、修复与验收记录

## 已核对

- 工作区原为 main / beac9c4，无未提交修改；fetch 后 origin/dev 为 e64ba342db18dc9c98d9241031bc6db17a993f09。
- 诊断分支 codex/macbook-ime-jitter，从上述 dev 创建。未发布。
- MacBook Pro / Mac16,8 / Apple M4 Pro；macOS 27.2 (26B123)。
- /Applications/Synca.app：org.haerth.synca，1.1.0 (63)。版本号与源码 SHA 的映射仍未证实。
- /Library/Input Methods/SogouWBInput.app：1.4.0；当前选中 com.sogou.inputmethod.wubi。
- defaults 只读查询的 AppleLanguages 首项 en-US，当前应用界面英文，与交接中的中文环境描述存在差异。没有修改语言或输入法设置；不能据此推断根因。

## 用户本次明确的触发步骤

先上屏一个汉字“是”，然后继续敲五笔编码 j，候选出现时文字/光标上下跳动。不能只检查空框首次输入。

用户提供的局部截图显示“是 + j”和搜狗候选；应用辅助功能树也读到输入框为“是j”。这证实现场文本状态，但静态截图不能独立证明移动幅度或区分文字基线变化与滚动。

此前要求用户切回聊天报告候选状态可能导致候选消失；后续应让用户保留输入焦点，或用可记录事件的本地诊断版本采集完整过程。

## 下一步

1. 本机未修改代码的可调试版本复现同一动作，核对运行路径、配置和 SHA。
2. 只记录几何、选区、属性和字体指标，不记录正文、账号、剪贴板或凭据。
3. 比较 marked text 前后和下一轮 run loop 的基线、line fragment、textContainerOrigin、clip bounds 与宿主高度。
4. 根因有证据后再作最小修复；同机真实五笔验证是验收条件，合成测试仅补充。

## 构建注意

项目实际配置为 Local、Production、Release，没有 Debug；传入 Debug 会落到 Local，不能把该产物当作 Production 对照。首次编译因执行限制阻止 Swift 宏插件失败；在允许正常运行编译插件后 Local 基线构建成功。Production 配置覆盖 SWIFT_OPTIMIZATION_LEVEL=-Onone 与 SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG 后，基线也已构建成功。未改变仓库构建配置。

## 本地运行核对

用户明确授权沿用现有线上账号环境运行本地调试版，禁止发送、删除记录和发布。Production 基线启动成功，显示既有账号和记录，未进行发送或删除操作。

- 源码：e64ba342db18dc9c98d9241031bc6db17a993f09，输入组件无修改。
- Bundle ID：org.haerth.synca。
- 本次进程 PID：12235。
- 实际运行路径：/private/tmp/synca-macbook-ime-baseline/Build/Products/Production/Synca.app/Contents/MacOS/Synca。
- TF 原进程 PID：1643，/Applications/Synca.app/Contents/MacOS/Synca；未替换或退出它。
- 本地输入框已聚焦，等待用户用真实搜狗五笔执行“是 → j → 候选”并确认是否跳动。

## 本地基线用户验证

用户确认未修复的本地基线仍跳动：先输入“是”再敲 j 出现候选时文字和光标上下抖动。用户补充首次“是”上屏时整个输入框变矮。因此“外框不动”不是所有输入阶段均成立的前提，必须同时记录宿主高度变化。

已添加临时诊断钩子，仅 DEBUG 与 SYNCA_IME_DIAGNOSTICS 同时启用时输出。日志文件为 /tmp/synca-ime-geometry-<PID>.jsonl，权限 0600；不写正文、账号、剪贴板或 token。记录 setMarkedText/insertText/unmarkText、textDidChange、布局、scrollRangeToVisible 与下一轮事件中的范围、长度、字体属性、glyph baseline、容器与滚动区域几何。布局查询可能使待处理布局提前完成，需确认诊断版仍复现后才能解释数据。尚未改变修复逻辑。

## 真实事件证据与修复候选

用户确认诊断版同样跳动且首次上屏变矮。日志 /tmp/synca-ime-geometry-19326.jsonl 记录了以下事件（backingScaleFactor=2）：

| 事件序号 | 状态 | 行高 | 基线（含 inset） | 文档高 | 可视高度 | clip 原点 |
| --- | --- | --- | --- | --- | --- | --- |
| 297 | 首次 Latin marked | 19 | 22 | 35 | 35 | 0,0 |
| 315 | 首个汉字提交后 | 16 | 21 | 34 | 34 | 0,0 |
| 327 | 汉字后新增 Latin marked | 19 | 22 | 35 | 34（随后变35） | 0,0 |
| 370 | 第二个汉字提交后 | 16 | 21 | 34 | 34 | 0,0 |
| 378 | 再次 Latin marked | 19 | 22 | 35 | 34（随后变35） | 0,0 |

字体分别为 .PingFangUITextSC-Regular 13（汉字）和 .SFNS-Regular 13（候选字母）。textContainerOrigin.y 始终为8，clip 原点始终为0；是字体回退/混排的自然行高和基线改变，并非内部滚动。初始 inputHeight=40 不是这次反复跳动的直接解释。

回归测试最初在原脚本的 -AppleLanguages '(en)' / '(zh-Hans)' 下仍通过；补充不覆盖 AppleLanguages 的本机原环境运行后，新增“汉字后候选的已有字形基线不得变化”断言失败。原环境测试与指定 en/zh-Hans 的字体度量不同，验证时必须保留原环境。未修改系统配置。

修复候选仅在 MacInputTextView 的 NSLayoutManagerDelegate 中为每行设置配置正文字体的最小基线和行高；保留原本更高的字形空间，不修改 marked-text 属性，不替换字体。新增回归在原环境、en、zh-Hans 三组通过，原环境高度35/35/35、基线22/22；语言对照高度34/34/34。旧测试中将单行高度硬编码为34的断言改为与该环境空框高度比较。

此处仍为候选修复；须完成真实搜狗五笔前后对比和未启用诊断日志的验收，不能用合成测试关闭问题。

## 修复后同机验收与剩余事项

用户确认带诊断的修复候选版：文字与光标不再跳，首个“是”上屏时输入框不再变矮。日志 /tmp/synca-ime-geometry-24861.jsonl 的126个 marked/commit 结束及下一轮样本，基线全部为22，文档及可视高度全部35，clip bounds 原点全部0。前后摘录见 macbook-ime-geometry-comparison.json，不含正文。

临时诊断函数、钩子和日志写入代码已全部移除；最终业务代码仅 MacInputTextView.swift（增加23行、删除2行）。使用 Production 原优化配置、无 DEBUG/SYNCA_IME_DIAGNOSTICS 显式覆盖编译成功：

`/tmp/synca-macbook-ime-final/Build/Products/Production/Synca.app`

最终版真实界面已验证：中英/组合 Emoji 多行粘贴、Cmd-Z 撤销、Cmd-Shift-Z 重做、12行长文本 Cmd-Up/Down 到首尾（滚动值0/1）、清除仅本次生成的未发送测试草稿后恢复占位与单行尺寸、附件选择入口打开并取消。账号记录数保持37待处理/3已完成，未发送或删除记录。未替换 /Applications/Synca.app，未发布、推送或创建PR。

扩展自动回归（移除日志后）在原进程环境、en、zh-Hans 三组全部通过：新增汉字/Latin候选基线与高度、候选属性与选区、回车不触发提交回调、取消候选与占位、多行/尾部换行/溢出首尾滚动、撤销重做、独立剪贴板的Unicode与换行、Shift-Return、大字号不截断。受限执行环境的独立剪贴板服务不可用，导致 paste 断言失败；允许访问该服务后同一测试三组通过，真实界面粘贴也通过。这不是线上输入缺陷。

构建仍有既有 AccessCenterView 的 WKNavigationDelegate 签名和 MessageListView 的 actor 隔离警告；本次 Mac 输入改动无编译警告。未扩大范围修改这些问题。

最终真机复核已通过：用户确认无诊断且正常优化的最终版，真实五笔输入不跳、不变矮，Esc取消候选和退格到空正常，占位无重叠；保留原语言与输入法设置。VoiceOver语音、浅色视觉和真实候选回车选词未单独人工验收；自动测试已检查候选阶段不会调用提交回调。

## 真机验收结束时状态

2026-11-10，用户完成最终本地版本真实搜狗五笔验收。此次报告的文字/光标跳动、首字上屏变矮和占位回归均通过；修复及测试保留在 codex/macbook-ime-jitter 本地工作区，未提交、未推送、未发布。上述未单独人工验收的扩展条件仍保持未验证状态。

## 提交授权

用户随后明确授权提交、推送修复与回归测试，创建目标为 dev 的 PR 并自动合并。提交前再次运行原环境/en/zh-Hans 输入回归及原生基础测试，均通过。该授权不包含手动发布、触发 TestFlight 或合并到 main。
