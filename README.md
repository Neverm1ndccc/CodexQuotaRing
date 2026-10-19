# Codex Quota Ring

macOS 原生菜单栏 Codex 额度监控工具。SwiftUI + AppKit，无第三方依赖，最低 macOS 14。生产界面只显示本机 Codex App Server 返回的真实数据；测试 Fixture 不会被打包到 Release 应用中。

## 下载

从 [GitHub Releases](https://github.com/Neverm1ndccc/CodexQuotaRing/releases/latest) 下载 `CodexQuotaRing-macOS.zip`，解压后得到应用。完整源码可通过本仓库克隆或下载源码包。


## 安装与首次启动

1. 将 `dist/Codex Quota Ring.app` 拖入 `/Applications`，双击启动。也可先在交付目录直接运行。
2. 菜单栏出现 20 pt 圆环（状态项宽 26 pt），默认不打开窗口，不显示 Dock 图标。
3. 点击圆环查看额度，右键打开快捷菜单。详情内的 Hide 隐藏卡片；再次点击图标或重新打开应用可恢复。Quit 退出应用及其 App Server。
4. 建议先将应用移入固定位置，再在 Settings 开启 Launch at Login。系统要求批准时，前往系统设置 → 通用 → 登录项。默认关闭开机启动。

需要已经安装且以 ChatGPT 账户登录的 Codex CLI。在 Terminal 检查：

```bash
codex --version
codex login status
# 若尚未登录：
codex login
```

安装说明：<https://developers.openai.com/codex/cli/>。API Key、Bedrock 等模式不等同于 ChatGPT 订阅额度，应用会明确显示不可用，不读取或混用 API 费用。

**CLI 路径设置：** Settings → Advanced → 填入 Codex 可执行文件的绝对路径，或 Choose… 选择文件，点击 Save & Reconnect。留空自动查找 PATH、Homebrew、`~/.local/bin`、npm/cargo/nvm/fnm 常见目录以及 Codex / ChatGPT 应用内置 CLI。手动路径无效时会直接报告错误，不偷偷回退到另一份 CLI。GUI 的 PATH 与 Terminal 不同，所以可能需要手动指定。

本次本机检测到的路径：

```text
/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex
```

## 显示规则

- 外圈蓝色：五小时剩余量；内圈绿色：每周剩余量。从顶部顺时针绘制。
- 只有一个有效窗口时，显示对应的单圈，不生成缺失窗口。
- 剩余 10%～30% 为橙色，低于 10% 为红色；过期数据灰色，轨道始终保留。设置可改为正常额度使用单色，低额度仍保留警示色。
- 0% 的前景为空，100% 为整圈；`null`、字段缺失、未知窗口时长均不解释为无限或满额。
- 无额度、未登录、缺少 CLI、加载状态显示中性图标及具体文字说明。
- 服务器明确限制普通用量、消费控制或额度已达上限时，卡片显示限制提示，图标变灰并显示红色中心标记；百分比不构成可用性承诺。
- 日期使用当前系统时区；卡片同时显示绝对重置日期和相对倒计时。到期仅重新读取服务端数据，不自行回满。
- 弹窗顶部位于当前屏幕摄像头安全区域下方，并额外留出一个菜单栏行高，避免刘海遮挡。
- 详情为原生 transient popover；再次点击图标、点击外部或 Hide 可收起。关闭后销毁详情视图，停止倒计时界面更新。

## 刷新、缓存与隐私

首次启动立即读取；默认每 60 秒刷新，可选择 120 或 300 秒。手动刷新合并并发请求；监听 `account/rateLimits/updated`，结合轮询、唤醒和网络恢复刷新。通知属于本应用自己的 App Server，不能保证看到其他 Codex 进程的所有变化。

请求超时为 15 秒；失败后按 5 / 15 / 30 / 60 / 120 秒退避，最大 120 秒。成功后恢复常规间隔。App Server 意外退出会进入相同重试流程；超时会关闭当前连接以便下一次重新初始化。只有一个额度读取流程和一个 App Server 实例。正常退出关闭 stdin、停止进程；子进程拒绝退出时两秒后强制结束。

通过 `account/read` 在额度读取前后核对身份；读取期间发生账户通知会丢弃本次结果并重新读取。切换身份、退出登录或手动重连会清理旧缓存。旧版 `account/read` 只保证返回 email / plan，无法可靠区分同邮箱下所有工作区切换；读取额度的 `accountId` 用于进一步校验。无法确认身份时不做持久化缓存；失败保留的数据明确标记“stale / current account source unverified”，不宣称其属于当前账户。

缓存仅保存额度、时间、身份 SHA-256 摘要和服务端限制状态，路径为：

```text
~/Library/Application Support/CodexQuotaRing/quota-cache.json
```

目录权限 0700，缓存文件 0600。首次连接未完成身份核实时不显示磁盘缓存。设置保存于 `com.local.CodexQuotaRing` 的 UserDefaults。

不读取、打印、上传或修改认证文件，不读取 Cookie，不创建 Codex 任务，不请求额外模型推理。App Server 自身按其正常行为复用和维护已有登录状态。stderr 持续排空但不记录；JSON 响应和敏感身份不写日志。诊断默认关闭，开启后仅向 macOS Unified Logging 写入同步成功/失败等固定事件。

## 构建、测试与打包

需要 Xcode 15 或更新版本、macOS SDK、Python 3（仅重新生成工程需要）。不需要安装 xcodegen。

```bash
cd /path/to/CodexQuotaRing
open CodexQuotaRing.xcodeproj
./Scripts/build.sh       # xcodebuild Release，arm64 + x86_64
./Scripts/test.sh        # xcodebuild XCTest，当前 Mac
./Scripts/package.sh     # 构建、复制 app、ad-hoc 签名、验证、ZIP
```

产物：`dist/Codex Quota Ring.app`、`dist/CodexQuotaRing-macOS.zip` 和完整源码包 `dist/CodexQuotaRing-source.zip`。

也可以使用 SwiftPM（方便核心测试和诊断；正式运行建议使用 .app）：

```bash
swift test
swift run QuotaProbe
# 指定 CLI：
swift run QuotaProbe /absolute/path/to/codex
```

`./Scripts/render-rings.sh` 可生成明确标记为测试数据的浅色/深色图标预览，用于离线视觉检查。

`QuotaProbe` 使用与应用相同的 Swift stdio 客户端，只打印额度、重置时间和账户身份是否可核实，不打印原始账户响应。仅在显式运行诊断工具时输出当前真实额度。

工程由 `Scripts/generate-project.py` 生成，已提交完整 `.xcodeproj` 和共享 Scheme。新增 Swift 文件后可重新运行该脚本；Xcode 工程和 SwiftPM 共用源代码。核心在 `Sources/Models` 和 `Sources/Services`，原生界面在 `Sources/App` 和 `Sources/Views`。

`Tests/Fixtures` 包含明确标识的额度 JSON 和纯本地 Python 协议模拟进程。测试覆盖单双圈、窗口位置互换、空值、未知时长、0/100%、窗口隔离、服务端限制、JSON 分帧、超时、通知、账户切换、过期缓存、退避、进程重启与退出清理、设置持久化。测试进程无需真实账户或网络；服务测试使用临时缓存和独立 UserDefaults 域。

## 协议与兼容性

依据官方文档 <https://developers.openai.com/codex/app-server/> 和本机 CLI 导出的 JSON Schema 开发。参考实现：<https://github.com/openai/codex/tree/main/codex-rs/app-server-protocol>。

握手为 `initialize` → 成功响应 → `initialized`；然后使用 `account/read` 和 `account/rateLimits/read`。请求 ID 唯一，响应匹配 ID，stdout 按行缓冲，支持分段及一次多条消息，stderr 独立排空。只接受只读功能；来自服务器的交互式请求返回 method-not-supported，不主动提供 Token。

优先选择 `rateLimitsByLimitId.codex`；回退选择 `rateLimits` 中 `limitId=codex`，或不存在多桶映射且没有模型名称的旧版匿名共享桶。其他模型桶不合并。遍历 primary/secondary，根据 300 / 10080 分钟识别窗口，未来字段忽略。

## 实测与限制

实际执行结果和验收范围见 [VALIDATION.md](VALIDATION.md)。

- Release 为 arm64 + x86_64 Universal 二进制，已在本机 Apple Silicon 实际运行；Intel 与 macOS 14 没有实体机运行验证。
- 交付版本是 **ad-hoc 本地签名，未 Developer ID 签名、未公证**。适合本机使用，跨机器传输可能被 Gatekeeper 拦截；公开分发需要自己的 Apple Developer 证书和公证。没有绕过系统安全设置的脚本。
- 开机启动已实现 ServiceManagement API，但未修改本机登录项、未实际重启验收。未实测物理断网/休眠、多显示器或真实账户切换；异常路径和账户保护有模拟进程回归测试。
- Codex App Server 为演进中的协议，其他 CLI 版本可能返回不支持窗口、身份不可核实或错误状态；不会用演示额度补齐。
