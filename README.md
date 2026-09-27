# Codex Usage Badge · Codex 用量条

为 Codex 桌面客户端增加侧栏额度圆环、项目文件夹颜色和会话 Token 色块。**本项目是非官方本地界面增强工具，与 OpenAI 无关联。**

[下载安装包](https://github.com/jaykinhoo9/codex-usage-badge/releases) · [问题反馈](https://github.com/jaykinhoo9/codex-usage-badge/issues) · [隐私与安全](SECURITY.md)

## 功能

- **订阅额度**：Plus 显示 5 小时和每周剩余额度两个圆环；Pro 系列显示周额度。剩余大于 50% 为绿色，10%～50% 为黄色，小于 10% 为红色。账户未返回的额度显示不可用。
- **文件夹颜色**：在侧栏项目菜单中选择七种颜色或恢复默认，保留原菜单操作。只改变客户端图标，不改变磁盘文件夹。
- **会话 Token**：会话前显示蓝色色块，鼠标悬停显示累计使用量，按亿、千万、万显示。蓝色由暗到亮对应：不足 100 万、100 万～不足 1000 万、1000 万～不足 1 亿、1 亿及以上。没有可用数据时显示灰色。
- **后台静默**：刷新不会启动、重启或激活桌面客户端。只有你主动点击启动入口时才打开客户端。

## 下载与要求

在 [Releases](https://github.com/jaykinhoo9/codex-usage-badge/releases) 下载对应系统的 ZIP，**不要选择 GitHub 自动生成的 Source code 压缩包作为安装包**。

| 系统 | 文件 | 状态 |
| --- | --- | --- |
| macOS | `CodexUsageBadge-macOS-0.8.0.zip` | 预发布版本；前代功能经过客户端实机验证，当前公开版通过独立测试 |
| Windows 10/11 | `CodexUsageBadge-Windows-0.8.0.zip` | 预发布版本；系统安装流程与真实客户端兼容性需区分，参见 CI 和下方限制 |

需要已安装并登录的 Codex 桌面客户端，以及 Node.js **24 或更高版本**。安装器优先寻找客户端可用的内置运行时，找不到时请安装 [Node.js 24 LTS](https://nodejs.org/en/download)。普通使用无需 Python、npm 或开发工具。

### macOS

1. 将 ZIP 完整解压。
2. 双击 `安装.command`。如系统不允许直接打开，可在终端进入解压目录，运行 `bash ./安装.command`。
3. 安装完成后完全退出客户端（`⌘Q`），从桌面 **Codex 用量条** 打开。
4. 以后用这个桌面入口启动。`诊断.command` 查看状态；`卸载.command` 停止后台并卸载。

自动寻找 `/Applications` 或用户 `Applications` 下的 `Codex.app` / `ChatGPT.app`，必须是包含 Codex CLI 的客户端。自定义应用位置可以在终端设置后安装：

```bash
CODEX_BADGE_APP="$HOME/Apps/Codex.app" bash ./安装.command
```

安装失败会尝试恢复旧版。不修改客户端原始应用包。macOS 生成的本地启动入口和源码 ZIP 均未经过 Apple 开发者签名或公证。

### Windows

1. 先打开客户端并登录一次，再完全退出（检查系统托盘）。
2. 将 ZIP 完整解压，双击 `Install.cmd`，无需管理员权限。
3. 从桌面 **Codex 用量条** 打开客户端。
4. `Status.cmd` 查看状态；`Uninstall.cmd` 卸载。升级时解压新版并重新执行 `Install.cmd`。

支持当前用户的商店包清单发现、普通安装路径，以及客户端缓存中的版本化 Node / CLI。路径变化后重新点击桌面入口会再次发现组件。详细设置见 [Windows 说明](docs/windows.md)。

安装器仅为当前进程设置 PowerShell `ExecutionPolicy Bypass`，不永久更改系统策略；企业策略限制脚本或本机调试时无法保证可用。

## 兼容性与数据含义

- 测试目标为具有当前导航栏与侧栏数据标记的 Codex 桌面客户端。它依赖客户端内部 UI 和本机调试接口；未来版本变化可能需要更新本工具。
- 订阅额度从本机 Codex App Server 的账号接口读取，需要该 CLI 与客户端使用同一账号和 `CODEX_HOME`。API Key 路线不一定有订阅额度。
- Token 是本机 `state_*.sqlite` 记录的 `tokens_used`：输入加输出累计值，包含缓存输入，不是当前上下文大小或付费金额。只读取当前侧栏会话 ID 与计数。
- **不跨系统读取 WSL / SSH / 远程主机的数据库。** 云端 ChatGPT 聊天、远程会话或缺少本地记录时显示灰色，不估算。
- 额度约每分钟刷新，Token 约每 5 秒刷新；过期或断线数据会标记不可用。文件夹颜色保存在该客户端本地存储中。
- 当前为预发布版本。自动化测试、Windows 安装流程测试和实际已登录 Windows 客户端的长期运行验证不是一回事，后者尚需更多设备反馈。

## 隐私

安装包不包含作者的账号、路径、截图、聊天、日志或本地数据库。不需要你提交任何 Token 或 API Key。工具无上传和遥测功能，安装包没有额外第三方运行时依赖；额度请求由客户端自带的 CLI 完成。

本机调试端口固定为 `127.0.0.1:39222`，仅处理客户端主窗口。开启调试后，同一设备上能访问此端口的其他程序也可能控制该客户端，请只在可信设备上使用；不要将端口转发到网络。诊断输出可能包含你自己机器的路径和额度，反馈问题前请先脱敏。

## 开发和构建

开发环境需 Node.js 24+、Python 3.10+；PowerShell 测试需 `pwsh` 或 Windows PowerShell 5.1。

```bash
git clone https://github.com/jaykinhoo9/codex-usage-badge.git
cd codex-usage-badge
npm ci
npx playwright install chromium --only-shell
python3 build.py
npm test
python3 scripts/build_release.py
npm run test:privacy
```

Windows 可用 `python` 代替 `python3`。测试使用临时目录与合成页面，不连接你正在使用的客户端。安装包在 `dist/`，含 SHA256 清单。源码构建只依赖 Python 标准库；Playwright 仅用于开发测试，不进入发布包。

## 许可

MIT，见 [LICENSE](LICENSE)。公开构建使用 Node.js 自带的 WebSocket 和标准库；不包含最初私人安装包的捆绑文件、客户端二进制或图标。Codex / ChatGPT 名称归各自权利人所有。
