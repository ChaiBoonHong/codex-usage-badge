$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$menu = Join-Path $root 'windows\Codex Usage Badge.cmd'
$version = (Get-Content -LiteralPath (Join-Path $root 'package.json') -Raw | ConvertFrom-Json).windowsVersion
$package = Join-Path $root ('dist/CodexUsageBadge-Windows-' + $version)
function Assert($Condition, [string]$Message) { if (!$Condition) { throw "ASSERT: $Message" } }

$source = Get-Content -LiteralPath $menu -Raw
Assert (Test-Path -LiteralPath $menu -PathType Leaf) 'single menu source exists'
foreach ($selection in @('1','2','3','4','5')) {
    Assert ($source -match ('if "%BADGE_MENU%"=="' + $selection + '"')) "menu accepts option $selection"
}
foreach ($action in @('Install','Launch','Status','Uninstall')) {
    Assert ($source -match ('call :RunAction ' + $action)) "menu routes $action"
}
$install = $source.IndexOf('call :RunAction Install')
$save = $source.IndexOf('Save your Codex work before restarting.')
$launch = $source.IndexOf('call :RunAction Launch')
Assert ($install -ge 0 -and $save -gt $install -and $launch -gt $save) 'install asks to save before restart'
Assert ($source -match 'Invalid option\. Choose a number from 1 to 5\.') 'invalid menu input is handled'
Assert ((Get-Content -LiteralPath (Join-Path $root 'windows\manage-windows.ps1') -Raw) -match "manual-launch\.cjs'\) --force") 'menu restart requests force mode after confirmation'
Assert ((Get-ChildItem -LiteralPath $package -Filter '*.cmd' -File).Name -ceq 'Codex Usage Badge.cmd') 'release contains only the menu command file'
Write-Host 'PASS one-file menu selections, routes, save-before-restart order, invalid input and release contents'
