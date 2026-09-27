# Windows 使用说明

完整解压 Releases 的 Windows ZIP 后，运行 `Install.cmd`。首次安装前先打开并登录客户端，使内置运行组件准备好；安装后从托盘或菜单完全退出，再使用桌面「Codex 用量条」入口。

安装到 `%LOCALAPPDATA%\CodexUsageBadge`，创建当前用户的桌面入口与启动项，不需要管理员权限。登录 Windows 时只启动隐藏后台，不会打开客户端。安装、更新、卸载具有归属检查与备份；不触碰客户端会话或账号目录。

## 运行环境

- Windows 10/11，Windows PowerShell 5.1 或更高版本。
- 已登录且包含 Codex CLI 的 Windows 桌面客户端。
- Node.js 24+，需要 `node:sqlite`。自动查找客户端 Node，或使用已安装的系统 Node。
- 原生 Windows 会话数据库。WSL 与远程环境暂不跨系统读取。

`Install.cmd` / `Launch.cmd` / `Status.cmd` / `Uninstall.cmd` 仅为本次 PowerShell 进程设置执行策略，不更改注册表或企业策略。脚本没有代码签名；设备策略禁止时请联系管理员。

## 自定义路径

只填写需要覆盖的参数，其余自动发现。以下示例路径需要换成实际位置：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\manage-windows.ps1 -Action Install -AppExe 'D:\Apps\Codex\Codex.exe' -NodeExe 'D:\Tools\nodejs\node.exe' -CodexBin 'D:\Apps\Codex\resources\codex.exe' -CodexHome 'D:\CodexData'
```

显式参数会保留，迁移后请重新指定。`CodexHome` 必须与客户端当前数据目录一致，否则可能读不到额度或 Token。

## 故障处理

- **未找到 Node / CLI**：先运行客户端一次；安装 Node.js 24 LTS；必要时显式指定路径。
- **已运行但不能连接**：普通入口启动时没有开启调试端口。完全退出客户端（含系统托盘）后使用桌面「Codex 用量条」。后台不会强行重启它。
- **更新后失效**：重新点击桌面入口或重跑安装器，自动寻找更新后的路径。
- **只有额度不可用**：确认使用支持额度查询的账号，且 CLI 和客户端的登录/数据目录一致。
- **Token 灰色**：可能没有本地记录，或当前是 WSL、远程、云端会话。

卸载时若客户端可连接，立即移除界面组件并清理颜色设置；否则组件会在下次完全重启后消失，颜色配置可能保留在客户端存储中。备份目录名以 `CodexUsageBadge.backup-` 或 `.uninstalled-` 开头，由用户自行决定何时删除。

CI 可验证 Windows 进程、快捷方式、后台停止和安装回滚等行为；不能代替各版本已登录客户端的 UI、商店启动和长期焦点测试。
