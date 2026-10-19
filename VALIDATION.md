# 验收记录 — 2026-10-20（Asia/Shanghai）

## 环境

- macOS 26.6.2 (25G83)，Apple Silicon。
- Xcode 26.4.1 (17E202)，Swift 6.3.1，最低部署 macOS 14。
- 本机 Codex CLI 0.163.0-alpha.10.2；`codex login status` 为 Logged in using ChatGPT。
- 使用安装版本的 `codex app-server generate-json-schema` 导出协议并核对官方 App Server 文档。

## 自动化结果（实际执行）

| 检查 | 结果 |
|---|---|
| `swift test` | 17 项 XCTest，0 失败；最终一轮约 8.43 秒 |
| `Scripts/test.sh` / `xcodebuild test` | 17 项，0 失败；TEST SUCCEEDED；约 8.30 秒 |
| Universal Release / `xcodebuild build` | arm64 + x86_64；BUILD SUCCEEDED |
| `codesign --verify --deep --strict` | 最终 .app 通过，本地 ad-hoc 签名 |
| 模拟进程崩溃自动恢复 | 通过；测试约 6.3 秒，包含首次通知后的身份重读及 5 秒退避 |
| 子进程正常关闭 | 通过；检查 PID 在截止时间前消失 |
| 身份变化及退出登录 | 通过；临时缓存清除，不显示旧账户额度 |
| 查询超时 | 通过；超时报错后后续请求可用 |
| 连续/分段消息、并发 ID 匹配、额度通知 | 通过 |
| 设置持久化 | 独立 UserDefaults 测试域通过 |

Xcode 的 AppIntents metadata 提取提示该应用没有 AppIntents 依赖，不影响构建。测试中观察到系统 linkd 的连接日志，测试本身全部成功。未将这些系统日志当作功能验证结果。

## 真实账户集成（实际执行）

`swift run QuotaProbe` 使用生产 Swift 客户端启动本机 CLI，握手、account/read、account/rateLimits/read 均成功，返回有效的五小时与每周窗口、服务端可用性状态及重置时间。应用显示的数值随真实用量变化。公开记录不包含个人账户的额度数值。

运行正式 .app 后通过原生界面读取及截图确认：

- 展示两个真实额度区域、线性进度条、绝对重置日期和相对倒计时。
- 点击刷新后同步时间变为 Updated now。
- 设置中的 CLI 路径、版本、连接 ready 和最近同步时间正确。
- Launch at Login 默认 off，Launch Hidden 默认 on。
- System / Dark 主题实际切换并检查外观，测试后恢复 System。
- Hide 收起详情后，后台应用及其唯一 App Server 继续运行；重新打开应用可恢复卡片。
- 多分钟后台运行后，缓存成功同步时间自动推进，确认定时刷新真实生效。
- 正常点击 Quit 后，实际应用 PID 及对应 App Server PID 均已消失。
- 一次隐藏后的瞬时进程采样为应用 0.0% CPU / 约 60 MB RSS，App Server 0.0% / 约 51 MB。此为单次观测，不是长期性能基准。

测试最初发现本机 App Server 初始发送 account/updated，导致原实现不断重连。已改为身份失效与请求版本校验，并加入服务层回归测试。回归与真实 UI 均确认修复。

## 图标视觉检查

`Scripts/render-rings.sh` 用生产矢量绘图器生成 `Documentation/ring-preview.png`；图上明确标识 TEST FIXTURES。已查看浅色/深色背景下的原尺寸及放大图，确认单双圈、0/100%、空数据、过期状态，圆心一致、间距清晰，弧线从顶部顺时针绘制。中性符号也已修正为随背景变化的灰色。

这不是物理切换 macOS 菜单栏主题的实机截图。圆环在实际 NSStatusItem 中由相同绘图器输出；原生界面的自动化观察会激活/重新打开 accessory 应用，不能据此单独证明 Launch Hidden 的系统登录行为。

## 未执行的系统级验收

- 未在 Intel 实体机、macOS 14 实体机运行；仅成功生成两个架构。
- 未更改本机登录项、未注销/重启，故不声称 Launch at Login 已完成实机重启验收。
- 未物理断网、休眠/唤醒或切换显示器；这些系统事件处理已实现，错误/重试逻辑通过模拟进程测试。
- 未切换用户真实账户；测试账户切换是纯本地 Fixture，真实工作区同邮箱身份识别存在 README 说明的限制。
- 未使用 Developer ID 证书，未公证。交付仅使用 ad-hoc 本地签名。

## 后续位置调整

用户反馈摄像头区域遮挡后，将卡片顶部限制为 `min(visibleFrame.maxY, screen.frame.maxY - safeAreaInsets.top) - NSStatusBar.system.thickness`，即安全区域下方再空出一个菜单栏行高，并限制底部不超出可见屏幕。保留原有 NSStatusItem 锚点、点击与收起行为。Universal Release 重新构建成功、打包及签名校验通过，更新进程已启动。该次原生自动化无法附着隐藏的 accessory 应用（超时），未声称完成新的实际刘海屏截图验证。
