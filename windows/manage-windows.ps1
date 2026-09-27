param(
    [ValidateSet('Install','Launch','Run','Uninstall','Status','Functions')][string]$Action = 'Status',
    [string]$AppExe, [string]$NodeExe, [string]$CodexBin, [string]$CodexHome
)
$ErrorActionPreference = 'Stop'
$script:Version = '0.8.0'
$script:Owner = 'local.codexusagebadge.windows'

function ConvertTo-NativeArgument([AllowEmptyString()][string]$Value) {
    # Microsoft C runtime argument quoting, including quotes and trailing backslashes.
    '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}
function Join-NativeArguments([string[]]$Values) {
    (@($Values | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
}
function Get-Setting($Object, [string]$Name) {
    if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $null
}
function Write-Utf8([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}
function Write-Json([string]$Path, $Value) {
    $temp = $Path + '.tmp-' + [guid]::NewGuid().ToString('N')
    $backup = $Path + '.replace-' + [guid]::NewGuid().ToString('N')
    try {
        Write-Utf8 $temp ($Value | ConvertTo-Json -Depth 8)
        # Windows PowerShell 5.1 coerces $null to an empty string for this .NET overload.
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temp, $Path, $backup) }
        else { [IO.File]::Move($temp, $Path) }
    } finally {
        foreach ($file in @($temp,$backup)) { if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force } }
    }
}
function Read-Json([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
}
function Assert-OwnedDirectory([string]$Path) {
    if (!(Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    $marker = Join-Path $Path '.codex-usage-badge-owner'
    if (!$item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        !(Test-Path -LiteralPath $marker -PathType Leaf) -or
        (Get-Content -LiteralPath $marker -Raw -Encoding UTF8).Trim() -ne $script:Owner) {
        throw "目录已存在且不属于本插件，未修改：$Path"
    }
}
function Initialize-Context {
    if ($env:OS -ne 'Windows_NT') { throw '此安装器仅供 Windows 使用。' }
    $script:InstallRoot = Join-Path $env:LOCALAPPDATA 'CodexUsageBadge'
    $script:ManagerPath = Join-Path $script:InstallRoot 'manage-windows.ps1'
    $script:ConfigPath = Join-Path $script:InstallRoot 'config.json'
    $script:StopPath = Join-Path $script:InstallRoot 'stop.request'
    $script:StatePath = Join-Path $script:InstallRoot 'worker.json'
    $script:PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $script:MutexName = 'Local\CodexUsageBadge.' + $sid
    $script:DesktopLink = Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'Codex 用量条.lnk'
    $script:StartupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'Codex Usage Badge Background.lnk'
}
function Invoke-Hidden([string]$Exe, [string[]]$Arguments, [int]$TimeoutMs = 12000) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Exe
    $info.Arguments = Join-NativeArguments $Arguments
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $info
    try {
        [void]$proc.Start()
        $out = $proc.StandardOutput.ReadToEndAsync()
        $err = $proc.StandardError.ReadToEndAsync()
        if (!$proc.WaitForExit($TimeoutMs)) { $proc.Kill(); throw '命令响应超时' }
        $result = [pscustomobject]@{ ExitCode = $proc.ExitCode; Output = $out.Result; Error = $err.Result }
        if ($result.ExitCode -ne 0) { throw "命令退出码 $($result.ExitCode)：$Exe" }
        return $result.Output.Trim()
    } finally { $proc.Dispose() }
}
function Get-ManifestExecutables($Manifest, [string]$Location) {
    foreach ($app in @($Manifest.Package.Applications.Application)) {
        $exe = [string]$app.Executable
        if ($exe -and ($exe -split '[/\\]')[-1] -match '^(Codex|ChatGPT)\.exe$') {
            Join-Path $Location $exe
        }
    }
}
function Test-DesktopExecutable([string]$Path) {
    return $Path -and (Test-Path -LiteralPath $Path -PathType Leaf) -and
        $Path -match '(?i)[/\\](Codex|ChatGPT)\.exe$' -and
        (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $Path) 'resources\app.asar') -PathType Leaf)
}
function Get-AppCandidates($Saved) {
    foreach ($proc in @(Get-Process -Name 'Codex','ChatGPT' -ErrorAction SilentlyContinue)) {
        try { if ($proc.Path) { $proc.Path } } catch {}
    }
    if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
        foreach ($pkg in @(Get-AppxPackage -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^OpenAI\.(Codex|ChatGPT)(\.|$)' } | Sort-Object Version -Descending)) {
            try { Get-ManifestExecutables (Get-AppxPackageManifest -Package $pkg.PackageFullName) $pkg.InstallLocation } catch {}
        }
    }
    foreach ($base in @((Join-Path $env:LOCALAPPDATA 'Programs'), $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($base) { foreach ($name in @('Codex','ChatGPT')) { Join-Path $base "$name\$name.exe" } }
    }
    if (Get-Setting $Saved 'AppExe') { $Saved.AppExe }
}
function Get-ChildExecutables([string]$Base, [string]$Suffix) {
    if (Test-Path -LiteralPath $Base -PathType Container) {
        Get-ChildItem -LiteralPath $Base -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending | ForEach-Object { Join-Path $_.FullName $Suffix }
    }
}
function Get-RuntimeCandidates([string]$AppPath, [ValidateSet('Node','CLI')][string]$Kind, $Saved) {
    $resources = Join-Path (Split-Path -Parent $AppPath) 'resources'
    $managed = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex'
    if ($Kind -eq 'Node') {
        Get-ChildExecutables (Join-Path $managed 'runtimes\cua_node') 'bin\node.exe'
        Join-Path $resources 'cua_node\bin\node.exe'
        if (Get-Setting $Saved 'NodeExe') { $Saved.NodeExe }
        $systemNode = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($systemNode) { $systemNode.Source }
    } else {
        foreach ($proc in @(Get-Process -Name 'codex' -ErrorAction SilentlyContinue)) {
            try { if ($proc.Path -and $proc.Path.StartsWith($managed + '\', [StringComparison]::OrdinalIgnoreCase)) { $proc.Path } } catch {}
        }
        Join-Path $managed 'bin\codex.exe'
        Get-ChildExecutables (Join-Path $managed 'bin') 'codex.exe'
        Join-Path $resources 'codex.exe'
        Join-Path $resources 'codex-cli\bin\codex.exe'
        Join-Path $resources 'codex-cli\codex.exe'
        if (Get-Setting $Saved 'CodexBin') { $Saved.CodexBin }
    }
}
function Select-Runtime([string[]]$Candidates, [string]$Kind) {
    foreach ($file in @($Candidates | Select-Object -Unique)) {
        if (!$file -or !(Test-Path -LiteralPath $file -PathType Leaf) -or [IO.Path]::GetExtension($file) -ne '.exe') { continue }
        try {
            if ($Kind -eq 'Node') {
                $code = 'if(+process.versions.node.split(".")[0]<24)process.exit(2);const{DatabaseSync}=require("node:sqlite");new DatabaseSync(":memory:").close();if(typeof WebSocket!=="function")process.exit(3);console.log("badge-runtime-ok")'
                if ((Invoke-Hidden $file @('-e',$code)) -ne 'badge-runtime-ok') { continue }
            } else {
                if ((Invoke-Hidden $file @('--version')) -notmatch '^codex-cli\s') { continue }
            }
            return (Get-Item -LiteralPath $file).FullName
        } catch {}
    }
    if ($Kind -eq 'Node') { throw '未找到可运行的 Node.js 24+（需 node:sqlite）。请先运行一次客户端，或安装 Node.js 24 LTS，再运行 Install.cmd。' }
    throw '未找到可运行的 Codex CLI。请先打开客户端一次，或使用 -CodexBin 指定客户端内置的 codex.exe。'
}
function Resolve-Configuration($Saved, $Overrides) {
    $custom = [ordered]@{}
    foreach ($key in @('AppExe','NodeExe','CodexBin','CodexHome')) {
        $value = Get-Setting (Get-Setting $Saved 'Overrides') $key
        if (Get-Setting $Overrides $key) { $value = $Overrides.$key }
        if ($value) { $custom[$key] = [string]$value }
    }
    $apps = @(Get-AppCandidates $Saved)
    if ($custom.AppExe) { $apps = @($custom.AppExe) }
    $selectedApp = $apps | Where-Object { Test-DesktopExecutable $_ } | Select-Object -First 1
    if (!$selectedApp) { throw '未找到 Windows Codex/ChatGPT 客户端。请先安装并运行客户端，或用 -AppExe 指定主程序。' }
    $nodes = @(Get-RuntimeCandidates $selectedApp 'Node' $Saved)
    $bins = @(Get-RuntimeCandidates $selectedApp 'CLI' $Saved)
    if ($custom.NodeExe) { $nodes = @($custom.NodeExe) }
    if ($custom.CodexBin) { $bins = @($custom.CodexBin) }
    $homePath = $env:CODEX_HOME
    if (!$homePath) { $homePath = Join-Path $env:USERPROFILE '.codex' }
    if (Get-Setting $Saved 'CodexHome') { $homePath = $Saved.CodexHome }
    if ($custom.CodexHome) { $homePath = $custom.CodexHome }
    if (![IO.Path]::IsPathRooted($homePath)) { throw 'CodexHome 必须是绝对路径。' }
    [pscustomobject]@{
        Schema = 1; Version = $script:Version; AppExe = $selectedApp
        NodeExe = Select-Runtime $nodes 'Node'; CodexBin = Select-Runtime $bins 'CLI'
        CodexHome = $homePath; Port = 39222; Overrides = [pscustomobject]$custom
    }
}
function Get-ManagerArguments([string]$Mode) {
    Join-NativeArguments @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$script:ManagerPath,'-Action',$Mode)
}
function Test-OwnedShortcut([string]$Path, [string]$Mode) {
    if (!(Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $false }
    $shell = New-Object -ComObject WScript.Shell
    try {
        $link = $shell.CreateShortcut($Path)
        return $link.TargetPath -ieq $script:PowerShell -and $link.Arguments -ceq (Get-ManagerArguments $Mode)
    } finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
}
function Assert-ShortcutAvailable([string]$Path, [string]$Mode) {
    if ((Test-Path -LiteralPath $Path) -and !(Test-OwnedShortcut $Path $Mode)) { throw "快捷方式名称已被其他文件占用，未修改：$Path" }
}
function Write-Shortcut([string]$Path, [string]$Mode, [string]$Icon) {
    Assert-ShortcutAvailable $Path $Mode
    $shell = New-Object -ComObject WScript.Shell
    try {
        $link = $shell.CreateShortcut($Path)
        $link.TargetPath = $script:PowerShell
        $link.Arguments = Get-ManagerArguments $Mode
        $link.WorkingDirectory = $script:InstallRoot
        $link.WindowStyle = 7
        $link.Description = 'Codex Usage Badge ' + $script:Version
        if ($Icon) { $link.IconLocation = $Icon + ',0' }
        $link.Save()
    } finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
}
function Test-Worker {
    $mutex = $null
    try {
        $mutex = [Threading.Mutex]::OpenExisting($script:MutexName)
        try { $acquired = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
        if ($acquired) { $mutex.ReleaseMutex(); return $false }
        return $true
    } catch [Threading.WaitHandleCannotBeOpenedException] { return $false }
    finally { if ($mutex) { $mutex.Dispose() } }
}
function Stop-Worker {
    if (!(Test-Worker)) { return }
    Assert-OwnedDirectory $script:InstallRoot
    Write-Utf8 $script:StopPath 'stop'
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while ((Test-Worker) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200 }
    if (Test-Worker) { throw '后台任务尚未退出，安装目录保持不变。请注销 Windows 后重试，或先运行 Status.cmd。' }
}
function Start-Worker {
    if (Test-Worker) { return }
    if (Test-Path -LiteralPath $script:StopPath) { Remove-Item -LiteralPath $script:StopPath -Force }
    if (Test-Path -LiteralPath $script:StatePath) { Remove-Item -LiteralPath $script:StatePath -Force }
    Start-Process -FilePath $script:PowerShell -ArgumentList (Get-ManagerArguments 'Run') -WindowStyle Hidden | Out-Null
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 200
        $state = Read-Json $script:StatePath
        if ((Test-Worker) -and (Get-Setting $state 'State') -eq 'running') { return }
        if ((Get-Setting $state 'State') -eq 'error') { throw $state.Message }
    }
    throw '后台启动超时，请运行 Status.cmd 查看状态。'
}
function Run-Worker {
    Assert-OwnedDirectory $script:InstallRoot
    $mutex = New-Object Threading.Mutex($false, $script:MutexName)
    $owned = $false
    $child = $null
    try {
        try { $owned = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
        if (!$owned) { return }
        # Run never launches or activates a desktop client, including at Windows login.
        while (!(Test-Path -LiteralPath $script:StopPath)) {
            try {
                $config = Resolve-Configuration (Read-Json $script:ConfigPath) $null
                Write-Json $script:ConfigPath $config
                $logRoot = Join-Path $script:InstallRoot 'logs'
                [void][IO.Directory]::CreateDirectory($logRoot)
                Get-ChildItem -LiteralPath $logRoot -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -Skip 4 | Remove-Item -Force
                $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
                $env:CODEX_BADGE_APP = $config.AppExe
                $env:CODEX_BADGE_BIN = $config.CodexBin
                $env:CODEX_HOME = $config.CodexHome
                $env:CODEX_BADGE_PORT = [string]$config.Port
                $env:CODEX_BADGE_STOP_FILE = $script:StopPath
                $child = Start-Process -FilePath $config.NodeExe -ArgumentList (Join-NativeArguments @((Join-Path $script:InstallRoot 'agent.cjs'))) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logRoot ($stamp + '.out.log')) -RedirectStandardError (Join-Path $logRoot ($stamp + '.err.log'))
                Start-Sleep -Milliseconds 800
                if ($child.HasExited) { throw "agent 退出码：$($child.ExitCode)" }
                Write-Json $script:StatePath @{ State = 'running'; Pid = $PID; AgentPid = $child.Id; Version = $script:Version; StartedAt = [DateTime]::UtcNow.ToString('o') }
                while (!$child.HasExited) {
                    if (Test-Path -LiteralPath $script:StopPath) {
                        if (!$child.WaitForExit(6000)) { $child.Kill(); $child.WaitForExit() }
                        break
                    }
                    Start-Sleep -Milliseconds 400
                }
                $child.Dispose(); $child = $null
            } catch {
                if ($child) { if (!$child.HasExited) { $child.Kill(); $child.WaitForExit() }; $child.Dispose(); $child = $null }
                Write-Json $script:StatePath @{ State = 'error'; Message = $_.Exception.Message; Version = $script:Version }
            }
            for ($i = 0; $i -lt 30 -and !(Test-Path -LiteralPath $script:StopPath); $i++) { Start-Sleep -Seconds 1 }
        }
    } finally {
        if ($child) { if (!$child.HasExited) { $child.Kill(); $child.WaitForExit() }; $child.Dispose() }
        if ($owned) { Write-Json $script:StatePath @{ State = 'stopped'; Version = $script:Version }; $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
function Save-ShortcutState {
    foreach ($path in @($script:DesktopLink,$script:StartupLink)) {
        $data = $null
        if (Test-Path -LiteralPath $path) { $data = [IO.File]::ReadAllBytes($path) }
        [pscustomobject]@{ Path = $path; Data = $data }
    }
}
function Restore-ShortcutState($Entries) {
    foreach ($entry in $Entries) {
        if ($null -ne $entry.Data) { [IO.File]::WriteAllBytes($entry.Path, $entry.Data) }
        elseif (Test-Path -LiteralPath $entry.Path) { Remove-Item -LiteralPath $entry.Path -Force }
    }
}
function Install-Badge($Overrides) {
    Assert-OwnedDirectory $script:InstallRoot
    Assert-ShortcutAvailable $script:DesktopLink 'Launch'
    Assert-ShortcutAvailable $script:StartupLink 'Run'
    $config = Resolve-Configuration (Read-Json $script:ConfigPath) $Overrides
    foreach ($name in @('agent.cjs','bridge.cjs')) {
        $file = Join-Path $PSScriptRoot $name
        if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "安装包不完整，请先解压 ZIP：$name" }
        [void](Invoke-Hidden $config.NodeExe @('--check',$file))
    }
    $stage = $script:InstallRoot + '.staging-' + [guid]::NewGuid().ToString('N')
    $backup = $script:InstallRoot + '.backup-' + [guid]::NewGuid().ToString('N')
    $links = @(Save-ShortcutState)
    $wasRunning = Test-Worker
    $swapped = $false
    $oldMoved = $false
    try {
        [void][IO.Directory]::CreateDirectory($stage)
        Write-Utf8 (Join-Path $stage '.codex-usage-badge-owner') $script:Owner
        foreach ($name in @('manage-windows.ps1','agent.cjs','bridge.cjs','Install.cmd','Launch.cmd','Status.cmd','Uninstall.cmd','README-Windows.md')) {
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $stage $name)
        }
        Write-Json (Join-Path $stage 'config.json') $config
        Stop-Worker
        if (Test-Path -LiteralPath $script:InstallRoot) { Move-Item -LiteralPath $script:InstallRoot -Destination $backup; $oldMoved = $true }
        Move-Item -LiteralPath $stage -Destination $script:InstallRoot; $swapped = $true
        Write-Shortcut $script:DesktopLink 'Launch' $config.AppExe
        Write-Shortcut $script:StartupLink 'Run' $config.AppExe
        Start-Worker
    } catch {
        $failure = $_
        if ($swapped) {
            Stop-Worker
            $failed = $script:InstallRoot + '.failed-' + [guid]::NewGuid().ToString('N')
            Move-Item -LiteralPath $script:InstallRoot -Destination $failed
        }
        if ($oldMoved) { Move-Item -LiteralPath $backup -Destination $script:InstallRoot }
        Restore-ShortcutState $links
        if ($wasRunning) { Start-Worker }
        throw $failure
    } finally {
        if (Test-Path -LiteralPath $stage) { Assert-OwnedDirectory $stage; Remove-Item -LiteralPath $stage -Recurse -Force }
    }
    Write-Host '安装成功。请完全退出客户端，再双击桌面「Codex 用量条」。'
    Write-Host '后台任务不会自行打开客户端。请保留此安装包，以便诊断或卸载。'
    if ($oldMoved) { Write-Host "旧版本备份：$backup" }
}
function Get-DebugPages {
    try {
        @(Invoke-RestMethod -Uri 'http://127.0.0.1:39222/json/list' -TimeoutSec 2 -UseBasicParsing) |
            Where-Object { $_.url -match '^app://-/index\.html(?:[?#]|$)' -and $_.url -notmatch '(?i)overlay' }
    } catch {}
}
function Launch-Badge {
    Assert-OwnedDirectory $script:InstallRoot
    if (!(Test-Path -LiteralPath $script:ConfigPath)) { throw '尚未安装，请先运行 Install.cmd。' }
    $config = Resolve-Configuration (Read-Json $script:ConfigPath) $null
    Stop-Worker
    Write-Json $script:ConfigPath $config
    Start-Worker
    if (@(Get-DebugPages).Count -gt 0) { return }
    $running = @(Get-Process -Name 'Codex','ChatGPT' -ErrorAction SilentlyContinue | Where-Object {
        try { Test-DesktopExecutable $_.Path } catch { $false }
    })
    if ($running.Count -gt 0) { throw '客户端已运行，但没有开启用量条连接。请从托盘菜单或客户端菜单完全退出，再双击桌面「Codex 用量条」。不会强制结束你的会话。' }
    # Only this explicit user action starts the GUI. The Run action cannot call this function.
    Start-Process -FilePath $config.AppExe -ArgumentList '--remote-debugging-address=127.0.0.1 --remote-debugging-port=39222' | Out-Null
    for ($i = 0; $i -lt 30; $i++) {
        if (@(Get-DebugPages).Count -gt 0) { return }
        Start-Sleep -Seconds 1
    }
    throw '客户端已启动，但调试连接尚未就绪。请运行 Status.cmd；首次登录完成后可再次双击桌面入口。'
}
function Uninstall-Badge {
    Assert-OwnedDirectory $script:InstallRoot
    if (!(Test-Path -LiteralPath $script:InstallRoot)) { Write-Host '未安装 Windows 用量条。'; return }
    Assert-ShortcutAvailable $script:DesktopLink 'Launch'
    Assert-ShortcutAvailable $script:StartupLink 'Run'
    Stop-Worker
    $config = Read-Json $script:ConfigPath
    $cleaned = $false
    try {
        $result = Invoke-Hidden $config.NodeExe @((Join-Path $script:InstallRoot 'bridge.cjs'),'cleanup')
        Write-Host $result
        $cleaned = $true
    } catch { Write-Host '当前窗口无法连接；界面组件将在下次完全退出并重新打开客户端后消失。已保存的文件夹颜色可能保留，重新安装后可重置。' }
    $links = @(Save-ShortcutState)
    $backup = $script:InstallRoot + '.uninstalled-' + [guid]::NewGuid().ToString('N')
    try {
        foreach ($entry in $links) { if ($null -ne $entry.Data) { Remove-Item -LiteralPath $entry.Path -Force } }
        Move-Item -LiteralPath $script:InstallRoot -Destination $backup
    } catch { Restore-ShortcutState $links; throw }
    Write-Host "已卸载。客户端、登录信息和聊天记录保持完整。可恢复备份：$backup"
}
function Show-Status {
    Write-Host "Codex 用量条 Windows $script:Version"
    Write-Host "安装目录：$script:InstallRoot"
    Write-Host "后台运行：$(Test-Worker)"
    $state = Read-Json $script:StatePath
    if ($state) { Write-Host ($state | ConvertTo-Json -Compress) }
    $config = Read-Json $script:ConfigPath
    if ($config) {
        foreach ($key in @('AppExe','NodeExe','CodexBin','CodexHome')) { Write-Host ($key + '：' + $config.$key) }
        try { Write-Host (Invoke-Hidden $config.NodeExe @((Join-Path $script:InstallRoot 'bridge.cjs'),'status')) }
        catch { Write-Host '尚未连接客户端窗口。请使用桌面「Codex 用量条」入口启动客户端。' }
    }
}

if ($Action -eq 'Functions') { return }
$operation = $null
$operationOwned = $false
try {
    Initialize-Context
    if ($Action -notin @('Run','Status')) {
        $operation = New-Object Threading.Mutex($false, ($script:MutexName + '.manage'))
        try { $operationOwned = $operation.WaitOne(0) } catch [Threading.AbandonedMutexException] { $operationOwned = $true }
        if (!$operationOwned) { throw '另一个安装、启动或卸载操作正在进行，请稍后重试。' }
    }
    switch ($Action) {
        'Install' { Install-Badge ([pscustomobject]@{ AppExe=$AppExe; NodeExe=$NodeExe; CodexBin=$CodexBin; CodexHome=$CodexHome }) }
        'Launch' { Launch-Badge }
        'Run' { Run-Worker }
        'Uninstall' { Uninstall-Badge }
        'Status' { Show-Status }
    }
} catch {
    if ($Action -eq 'Launch') {
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Codex 用量条')
    } else { Write-Host ('错误：' + $_.Exception.Message) -ForegroundColor Red }
    exit 1
} finally {
    if ($operationOwned) { $operation.ReleaseMutex() }
    if ($operation) { $operation.Dispose() }
}
