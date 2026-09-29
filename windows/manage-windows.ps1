param(
    [ValidateSet('Install','Launch','Run','Uninstall','Status','Functions')][string]$Action = 'Status',
    [string]$AppExe, [string]$NodeExe, [string]$CodexBin, [string]$CodexHome
)
$ErrorActionPreference = 'Stop'
$script:Version = '0.11.12'
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
function Write-Event([string]$Action, [string]$Step, $Data = @{}) {
    $logRoot = Join-Path $script:InstallRoot 'logs'
    [void][IO.Directory]::CreateDirectory($logRoot)
    $entry = [ordered]@{ timestamp = [DateTime]::UtcNow.ToString('o'); version = $script:Version; action = $Action; step = $Step; data = $Data }
    [IO.File]::AppendAllText((Join-Path $logRoot 'events.jsonl'), (($entry | ConvertTo-Json -Compress -Depth 4) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
}
function Assert-OwnedDirectory([string]$Path) {
    if (!(Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    $marker = Join-Path $Path '.codex-usage-badge-owner'
    if (!$item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        !(Test-Path -LiteralPath $marker -PathType Leaf) -or
        (Get-Content -LiteralPath $marker -Raw -Encoding UTF8).Trim() -ne $script:Owner) {
        throw "The existing directory is not owned by Codex Usage Badge; it was not changed: $Path"
    }
}
function Initialize-Context {
    if ($env:OS -ne 'Windows_NT') { throw 'This installer is for Windows only.' }
    $script:InstallRoot = Join-Path $env:LOCALAPPDATA 'CodexUsageBadge'
    $script:ManagerPath = Join-Path $script:InstallRoot 'manage-windows.ps1'
    $script:ConfigPath = Join-Path $script:InstallRoot 'config.json'
    $script:StopPath = Join-Path $script:InstallRoot 'stop.request'
    $script:StatePath = Join-Path $script:InstallRoot 'worker.json'
    $script:PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $script:MutexName = 'Local\CodexUsageBadge.' + $sid
    # Alternate LocalAppData roots (including disposable tests) must not share the real install's worker.
    $defaultRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CodexUsageBadge'
    if (![IO.Path]::GetFullPath($script:InstallRoot).Equals([IO.Path]::GetFullPath($defaultRoot), [StringComparison]::OrdinalIgnoreCase)) {
        $hash = [Security.Cryptography.SHA256]::Create()
        try { $suffix = [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($script:InstallRoot).ToLowerInvariant()))).Replace('-','') }
        finally { $hash.Dispose() }
        $script:MutexName += '.' + $suffix
    }
    $script:DesktopLink = Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'Codex Usage Badge.lnk'
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
        if (!$proc.WaitForExit($TimeoutMs)) { $proc.Kill(); throw 'Command response timed out' }
        $result = [pscustomobject]@{ ExitCode = $proc.ExitCode; Output = $out.Result; Error = $err.Result }
        if ($result.ExitCode -ne 0) { throw "Command exited with code $($result.ExitCode): $Exe" }
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
    if ($Kind -eq 'Node') { throw 'No usable Node.js 24+ runtime with node:sqlite was found. Open Codex once or install Node.js 24 LTS, then rerun Codex Usage Badge.cmd.' }
    throw 'No usable Codex CLI was found. Open Codex once or use -CodexBin to specify its bundled codex.exe.'
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
    if (!$selectedApp) { throw 'No Windows Codex/ChatGPT desktop app was found. Install and open it once, or use -AppExe to specify the executable.' }
    $nodes = @(Get-RuntimeCandidates $selectedApp 'Node' $Saved)
    $bins = @(Get-RuntimeCandidates $selectedApp 'CLI' $Saved)
    if ($custom.NodeExe) { $nodes = @($custom.NodeExe) }
    if ($custom.CodexBin) { $bins = @($custom.CodexBin) }
    $homePath = $env:CODEX_HOME
    if (!$homePath) { $homePath = Join-Path $env:USERPROFILE '.codex' }
    if (Get-Setting $Saved 'CodexHome') { $homePath = $Saved.CodexHome }
    if ($custom.CodexHome) { $homePath = $custom.CodexHome }
    if (![IO.Path]::IsPathRooted($homePath)) { throw 'CodexHome must be an absolute path.' }
    [pscustomobject]@{
        Schema = 1; Version = $script:Version; AppExe = $selectedApp
        NodeExe = Select-Runtime $nodes 'Node'; CodexBin = Select-Runtime $bins 'CLI'
        CodexHome = $homePath; Port = 39222; Overrides = [pscustomobject]$custom
    }
}
function Get-ManagerArguments([string]$Mode) {
    Join-NativeArguments @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$script:ManagerPath,'-Action',$Mode)
}
function Initialize-ShortcutApi {
    if ('CodexUsageBadge.Shortcuts' -as [type]) { return }
    # WScript.Shell can lose Unicode shortcut paths on non-Chinese Windows locales.
    # Use the Unicode shell-link interface and IPersistFile directly.
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
namespace CodexUsageBadge {
    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    internal class ShellLink {}
    [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IShellLinkW {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder path, int size, IntPtr findData, uint flags);
        void GetIDList(out IntPtr list);
        void SetIDList(IntPtr list);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder value, int size);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string value);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder value, int size);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string value);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder value, int size);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string value);
        void GetHotkey(out short value);
        void SetHotkey(short value);
        void GetShowCmd(out int value);
        void SetShowCmd(int value);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder value, int size, out int index);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string value, int index);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string value, uint reserved);
        void Resolve(IntPtr window, uint flags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string value);
    }
    public sealed class LinkInfo { public string TargetPath; public string Arguments; }
    public static class Shortcuts {
        public static void Write(string file, string target, string arguments, string directory, string icon) {
            object obj = new ShellLink();
            try {
                IShellLinkW link = (IShellLinkW)obj;
                link.SetPath(target); link.SetArguments(arguments); link.SetWorkingDirectory(directory);
                link.SetShowCmd(7); link.SetDescription("Codex Usage Badge");
                if (!String.IsNullOrEmpty(icon)) link.SetIconLocation(icon, 0);
                ((IPersistFile)obj).Save(file, true);
            } finally { Marshal.ReleaseComObject(obj); }
        }
        public static LinkInfo Read(string file) {
            object obj = new ShellLink();
            try {
                ((IPersistFile)obj).Load(file, 0);
                IShellLinkW link = (IShellLinkW)obj;
                StringBuilder target = new StringBuilder(32768), args = new StringBuilder(32768);
                link.GetPath(target, target.Capacity, IntPtr.Zero, 4); link.GetArguments(args, args.Capacity);
                return new LinkInfo { TargetPath = target.ToString(), Arguments = args.ToString() };
            } finally { Marshal.ReleaseComObject(obj); }
        }
    }
}
'@
}
function Test-OwnedShortcut([string]$Path, [string]$Mode) {
    if (!(Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $false }
    Initialize-ShortcutApi
    try {
        $link = [CodexUsageBadge.Shortcuts]::Read($Path)
        return $link.TargetPath -ieq $script:PowerShell -and $link.Arguments -ceq (Get-ManagerArguments $Mode)
    } catch { return $false }
}
function Assert-ShortcutAvailable([string]$Path, [string]$Mode) {
    if ((Test-Path -LiteralPath $Path) -and !(Test-OwnedShortcut $Path $Mode)) { throw "The shortcut name is already used by another file; it was not changed: $Path" }
}
function Write-Shortcut([string]$Path, [string]$Mode, [string]$Icon) {
    Assert-ShortcutAvailable $Path $Mode
    Initialize-ShortcutApi
    [CodexUsageBadge.Shortcuts]::Write($Path, $script:PowerShell, (Get-ManagerArguments $Mode), $script:InstallRoot, $Icon)
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
    if (!(Test-Path -LiteralPath $script:InstallRoot)) { return }
    Assert-OwnedDirectory $script:InstallRoot
    if (!(Test-Worker)) { Write-Event 'worker-stop' 'skipped' @{ reason = 'not-running' }; return }
    Write-Event 'worker-stop' 'requested' @{ timeoutSeconds = 30 }
    Write-Utf8 $script:StopPath 'stop'
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while ((Test-Worker) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200 }
    if (Test-Worker) { Write-Event 'worker-stop' 'failed' @{ reason = 'timeout' }; throw 'The background worker did not stop; the installation directory is unchanged. Sign out of Windows and retry, or choose Check status from Codex Usage Badge.cmd first.' }
    Write-Event 'worker-stop' 'completed' @{}
}
function Start-Worker {
    Assert-OwnedDirectory $script:InstallRoot
    if (Test-Worker) { Write-Event 'worker-start' 'skipped' @{ reason = 'already-running' }; return }
    Write-Event 'worker-start' 'requested' @{ timeoutSeconds = 25 }
    if (Test-Path -LiteralPath $script:StopPath) { Remove-Item -LiteralPath $script:StopPath -Force }
    if (Test-Path -LiteralPath $script:StatePath) { Remove-Item -LiteralPath $script:StatePath -Force }
    Start-Process -FilePath $script:PowerShell -ArgumentList (Get-ManagerArguments 'Run') -WindowStyle Hidden | Out-Null
    $deadline = [DateTime]::UtcNow.AddSeconds(25)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 200
        $state = Read-Json $script:StatePath
        if ((Test-Worker) -and (Get-Setting $state 'State') -eq 'running') { Write-Event 'worker-start' 'completed' @{ state = 'running' }; return }
        if ((Get-Setting $state 'State') -eq 'error') { Write-Event 'worker-start' 'failed' @{ reason = 'worker-error' }; throw $state.Message }
    }
    Write-Event 'worker-start' 'failed' @{ reason = 'timeout' }
    throw 'Background startup timed out. Choose Check status from Codex Usage Badge.cmd for details.'
}
function Run-Worker {
    Assert-OwnedDirectory $script:InstallRoot
    $mutex = New-Object Threading.Mutex($false, $script:MutexName)
    $owned = $false
    $child = $null
    $startup = $null
    try {
        try { $owned = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
        if (!$owned) { return }
        # Login only starts observers. The guarded helper completes a NEW user launch.
        while (!(Test-Path -LiteralPath $script:StopPath)) {
            try {
                $config = Resolve-Configuration (Read-Json $script:ConfigPath) $null
                Write-Json $script:ConfigPath $config
                $logRoot = Join-Path $script:InstallRoot 'logs'
                [void][IO.Directory]::CreateDirectory($logRoot)
                Get-ChildItem -LiteralPath $logRoot -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -Skip 8 | Remove-Item -Force
                $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
                $env:CODEX_BADGE_APP = $config.AppExe
                $env:CODEX_BADGE_BIN = $config.CodexBin
                $env:CODEX_HOME = $config.CodexHome
                $env:CODEX_BADGE_PORT = [string]$config.Port
                $env:CODEX_BADGE_STOP_FILE = $script:StopPath
                $child = Start-Process -FilePath $config.NodeExe -ArgumentList (Join-NativeArguments @((Join-Path $script:InstallRoot 'agent.cjs'))) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logRoot ($stamp + '.out.log')) -RedirectStandardError (Join-Path $logRoot ($stamp + '.err.log'))
                $startedAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                $startup = Start-Process -FilePath $config.NodeExe -ArgumentList (Join-NativeArguments @((Join-Path $script:InstallRoot 'startup/windows.cjs'))) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logRoot ($stamp + '.startup.out.log')) -RedirectStandardError (Join-Path $logRoot ($stamp + '.startup.err.log'))
                $ready = $false
                $deadline = [DateTime]::UtcNow.AddSeconds(20)
                while ([DateTime]::UtcNow -lt $deadline -and !(Test-Path -LiteralPath $script:StopPath)) {
                    if ($child.HasExited -or $startup.HasExited) { throw 'A background process exited early. Check the logs folder.' }
                    $receipt = Read-Json (Join-Path $script:InstallRoot 'startup/state.json')
                    if ((Get-Setting $receipt 'event') -eq 'watching' -and $receipt.updatedAt -ge $startedAt) { $ready = $true; break }
                    Start-Sleep -Milliseconds 200
                }
                if (!$ready) { throw 'The native startup monitor did not become ready. Check the logs.' }
                Write-Json $script:StatePath @{ State = 'running'; Pid = $PID; AgentPid = $child.Id; StartupPid = $startup.Id; Version = $script:Version; StartedAt = [DateTime]::UtcNow.ToString('o') }
                while (!$child.HasExited -and !$startup.HasExited) {
                    if (Test-Path -LiteralPath $script:StopPath) {
                        if (!$startup.WaitForExit(14000)) { $startup.Kill(); $startup.WaitForExit() }
                        if (!$child.WaitForExit(6000)) { $child.Kill(); $child.WaitForExit() }
                        break
                    }
                    Start-Sleep -Milliseconds 400
                }
                if (!$child.HasExited) { $child.Kill(); $child.WaitForExit() }
                $child.Dispose(); $child = $null
                if (!$startup.HasExited) { $startup.Kill(); $startup.WaitForExit() }
                $startup.Dispose(); $startup = $null
            } catch {
                if ($child) { if (!$child.HasExited) { $child.Kill(); $child.WaitForExit() }; $child.Dispose(); $child = $null }
                if ($startup) { if (!$startup.HasExited) { $startup.Kill(); $startup.WaitForExit() }; $startup.Dispose(); $startup = $null }
                Write-Json $script:StatePath @{ State = 'error'; Message = $_.Exception.Message; Version = $script:Version }
            }
            for ($i = 0; $i -lt 30 -and !(Test-Path -LiteralPath $script:StopPath); $i++) { Start-Sleep -Seconds 1 }
        }
    } finally {
        if ($startup) { if (!$startup.HasExited) { $startup.Kill(); $startup.WaitForExit() }; $startup.Dispose() }
        if ($child) { if (!$child.HasExited) { $child.Kill(); $child.WaitForExit() }; $child.Dispose() }
        if ($owned) { Write-Json $script:StatePath @{ State = 'stopped'; Version = $script:Version }; $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
function Save-ShortcutState {
    foreach ($path in @($script:DesktopLink,$script:StartupLink)) {
        if ($path -eq $script:DesktopLink -and !(Test-OwnedShortcut $path 'Launch')) { continue }
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
    Assert-ShortcutAvailable $script:StartupLink 'Run'
    if (Test-Path -LiteralPath $script:InstallRoot) { Write-Event 'install' 'requested' @{ update = $true } }
    $config = Resolve-Configuration (Read-Json $script:ConfigPath) $Overrides
    foreach ($name in @('agent.cjs','bridge.cjs','startup/controller.cjs','startup/windows.cjs','startup/manual-launch.cjs')) {
        $file = Join-Path $PSScriptRoot $name
        if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "The package is incomplete. Fully extract the ZIP first: $name" }
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
        if (Test-Path -LiteralPath $script:InstallRoot) { Write-Event 'install' 'staging-created' @{ update = $true } }
        Write-Utf8 (Join-Path $stage '.codex-usage-badge-owner') $script:Owner
        foreach ($name in @('Codex Usage Badge.cmd','manage-windows.ps1','agent.cjs','bridge.cjs')) {
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $stage $name)
        }
        [void][IO.Directory]::CreateDirectory((Join-Path $stage 'startup'))
        foreach ($name in @('controller.cjs','manual-launch.cjs','windows.cjs','windows-bridge.ps1','windows-native.cs')) {
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('startup/' + $name)) -Destination (Join-Path $stage ('startup/' + $name))
        }
        Write-Json (Join-Path $stage 'config.json') $config
        Stop-Worker
        $oldReceipt = Join-Path $script:InstallRoot 'startup/state.json'
        if (Test-Path -LiteralPath $oldReceipt) { Copy-Item -LiteralPath $oldReceipt -Destination (Join-Path $stage 'startup/state.json') }
        if (Test-Path -LiteralPath $script:InstallRoot) { Move-Item -LiteralPath $script:InstallRoot -Destination $backup; $oldMoved = $true }
        Move-Item -LiteralPath $stage -Destination $script:InstallRoot; $swapped = $true
        Write-Event 'install' 'files-replaced' @{ upgraded = $oldMoved }
        if (Test-OwnedShortcut $script:DesktopLink 'Launch') { Remove-Item -LiteralPath $script:DesktopLink -Force }
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
    Write-Host 'Installation succeeded. Return to Codex Usage Badge.cmd, save your work, then choose Restart Codex with Badge.'
    Write-Event 'install' 'completed' @{ upgraded = $oldMoved }
    if ($oldMoved) { Write-Host "Previous version backup: $backup" }
}
function Get-DebugPages {
    try {
        @(Invoke-RestMethod -Uri 'http://127.0.0.1:39222/json/list' -TimeoutSec 2 -UseBasicParsing) |
            Where-Object { $_.url -match '^app://-/index\.html(?:[?#]|$)' -and $_.url -notmatch '(?i)overlay' }
    } catch {}
}
function Launch-Badge {
    Assert-OwnedDirectory $script:InstallRoot
    if (!(Test-Path -LiteralPath $script:ConfigPath)) { throw 'Not installed. Choose Install or update from Codex Usage Badge.cmd first.' }
    $config = Resolve-Configuration (Read-Json $script:ConfigPath) $null
    Write-Event 'restart' 'requested' @{ mode = 'confirmed-force'; port = $config.Port }
    Stop-Worker
    try {
        if (Test-Path -LiteralPath $script:StopPath) { Remove-Item -LiteralPath $script:StopPath -Force }
        & $config.NodeExe (Join-Path $script:InstallRoot 'startup\manual-launch.cjs') --force
        if ($LASTEXITCODE -ne 0) { throw 'Codex could not be reopened with the Badge connection.' }
        Write-Event 'restart' 'reopened' @{ mode = 'confirmed-force' }
        Start-Worker
    } catch {
        Write-Event 'restart' 'failed' @{ reason = $_.Exception.GetType().Name }
        Start-Worker
        throw
    }
}
function Uninstall-Badge {
    Assert-OwnedDirectory $script:InstallRoot
    if (!(Test-Path -LiteralPath $script:InstallRoot)) { Write-Host 'Codex Usage Badge is not installed.'; return }
    Assert-ShortcutAvailable $script:StartupLink 'Run'
    Write-Event 'uninstall' 'requested' @{}
    Stop-Worker
    $config = Read-Json $script:ConfigPath
    $cleaned = $false
    try {
        $result = Invoke-Hidden $config.NodeExe @((Join-Path $script:InstallRoot 'bridge.cjs'),'cleanup')
        Write-Host $result
        $cleaned = $true
        Write-Event 'uninstall' 'ui-cleanup-completed' @{}
    } catch { Write-Event 'uninstall' 'ui-cleanup-skipped' @{ reason = $_.Exception.GetType().Name }; Write-Host 'The current window cannot be reached. UI components disappear after the next full restart; saved project colors may remain and can be reset by reinstalling.' }
    $links = @(Save-ShortcutState)
    $backup = $script:InstallRoot + '.uninstalled-' + [guid]::NewGuid().ToString('N')
    try {
        if (Test-OwnedShortcut $script:DesktopLink 'Launch') { Remove-Item -LiteralPath $script:DesktopLink -Force }
        if (Test-OwnedShortcut $script:StartupLink 'Run') { Remove-Item -LiteralPath $script:StartupLink -Force }
        Move-Item -LiteralPath $script:InstallRoot -Destination $backup
    } catch { Restore-ShortcutState $links; throw }
    Write-Host "Uninstalled. Your Codex app, sign-in, and chats remain intact. Recoverable backup: $backup"
}
function Show-Status {
    if (Test-Path -LiteralPath $script:InstallRoot) { Assert-OwnedDirectory $script:InstallRoot; Write-Event 'status' 'requested' @{ workerRunning = [bool](Test-Worker) } }
    Write-Host "Codex Usage Badge Windows $script:Version"
    Write-Host "Install directory: $script:InstallRoot"
    Write-Host "Background running: $(Test-Worker)"
    Write-Host "Detailed lifecycle log: $(Join-Path $script:InstallRoot 'logs\events.jsonl')"
    $state = Read-Json $script:StatePath
    if ($state) { Write-Host ($state | ConvertTo-Json -Compress) }
    $receipt = Read-Json (Join-Path $script:InstallRoot 'startup/state.json')
    if ($receipt) { Write-Host ('Automatic loading: ' + ($receipt | ConvertTo-Json -Compress)) }
    $config = Read-Json $script:ConfigPath
    if ($config) {
        foreach ($key in @('AppExe','NodeExe','CodexBin','CodexHome')) { Write-Host ($key + '：' + $config.$key) }
        try { Write-Host (Invoke-Hidden $config.NodeExe @((Join-Path $script:InstallRoot 'bridge.cjs'),'status')) }
        catch { Write-Host 'No connected Codex window. Save your work, then choose Restart Codex with Badge from Codex Usage Badge.cmd.' }
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
        if (!$operationOwned) { throw 'Another install, launch, or uninstall operation is already running. Try again shortly.' }
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
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Codex Usage Badge')
    } else { Write-Host ('Error: ' + $_.Exception.Message) -ForegroundColor Red }
    exit 1
} finally {
    if ($operationOwned) { $operation.ReleaseMutex() }
    if ($operation) { $operation.Dispose() }
}
