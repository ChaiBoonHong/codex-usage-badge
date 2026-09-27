# Native Windows smoke test with disposable data and a synthetic CLI; no real account/client.
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Windows runner required' }
$root = Split-Path -Parent $PSScriptRoot
$package = Join-Path $root 'dist/CodexUsageBadge-Windows-0.8.0'
. (Join-Path $package 'manage-windows.ps1') -Action Functions
$temp = Join-Path ([IO.Path]::GetTempPath()) ('badge-native-中文 空格-' + [guid]::NewGuid().ToString('N'))
$originalLocal = $env:LOCALAPPDATA
$originalCodeHome = $env:CODEX_HOME
$originalEnv = @{}
foreach ($key in @('CODEX_BADGE_APP','CODEX_BADGE_BIN','CODEX_BADGE_PORT','CODEX_BADGE_STOP_FILE')) { $originalEnv[$key] = [Environment]::GetEnvironmentVariable($key) }
function Assert($Condition, [string]$Message) { if (!$Condition) { throw $Message } }
try {
    [void][IO.Directory]::CreateDirectory($temp)
    $env:LOCALAPPDATA = $temp
    $env:CODEX_HOME = Join-Path $temp 'synthetic-home'
    [void][IO.Directory]::CreateDirectory($env:CODEX_HOME)
    $gui = Join-Path $temp 'Fixture/Codex.exe'
    [void][IO.Directory]::CreateDirectory((Join-Path (Split-Path $gui) 'resources'))
    Write-Utf8 (Join-Path (Split-Path $gui) 'resources/app.asar') 'synthetic fixture'
    $cli = Join-Path $temp 'codex.exe'
    Add-Type -TypeDefinition 'public class BadgeFixture { public static void Main(string[] args) { System.Console.WriteLine("codex-cli fixture"); } }' -OutputAssembly $cli -OutputType ConsoleApplication
    Copy-Item -LiteralPath $cli -Destination $gui
    $runtime = (Get-Command node.exe -CommandType Application | Select-Object -First 1).Source
    Initialize-Context
    # Use real .lnk APIs but keep the links away from the runner's startup/desktop folders.
    $script:DesktopLink = Join-Path $temp 'Test Desktop.lnk'
    $script:StartupLink = Join-Path $temp 'Test Startup.lnk'
    Install-Badge ([pscustomobject]@{AppExe=$gui;NodeExe=$runtime;CodexBin=$cli;CodexHome=$env:CODEX_HOME})
    Assert (Test-Worker) 'Native hidden supervisor did not start'
    Assert (Test-OwnedShortcut $script:DesktopLink 'Launch') 'Desktop shortcut target mismatch'
    Assert (Test-OwnedShortcut $script:StartupLink 'Run') 'Startup shortcut target mismatch'
    $state = Read-Json $script:StatePath
    $agentPid = $state.AgentPid
    Assert ((Get-Process -Id $agentPid).ProcessName -eq 'node') 'Expected native Node agent'
    $duplicate = Start-Process -FilePath $script:PowerShell -ArgumentList (Get-ManagerArguments 'Run') -WindowStyle Hidden -PassThru
    Assert ($duplicate.WaitForExit(15000)) 'Duplicate worker was not rejected'
    $duplicate.Dispose()
    Assert ((Read-Json $script:StatePath).AgentPid -eq $agentPid) 'Duplicate start replaced running worker'
    Stop-Worker
    Assert (!(Test-Worker)) 'Native stop-file shutdown failed'
    Assert (!(Get-Process -Id $agentPid -ErrorAction SilentlyContinue)) 'Agent process still running after stop'
    Start-Worker
    Assert (Test-Worker) 'Native worker restart failed'
    Uninstall-Badge
    Assert (!(Test-Worker)) 'Supervisor still running after uninstall'
    Assert (!(Test-Path -LiteralPath $script:InstallRoot)) 'Install directory not archived'
    Assert (!(Test-Path -LiteralPath $script:StartupLink)) 'Startup shortcut not removed'
    Write-Host 'PASS Windows PowerShell 5.1 native install, real COM shortcuts, hidden process startup, singleton mutex, graceful stop, restart, uninstall'
} finally {
    try { Stop-Worker } catch {}
    $env:LOCALAPPDATA = $originalLocal
    $env:CODEX_HOME = $originalCodeHome
    foreach ($key in $originalEnv.Keys) { [Environment]::SetEnvironmentVariable($key, $originalEnv[$key]) }
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
