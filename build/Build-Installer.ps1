$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Compile.ps1')

$dist = Join-Path $repo 'dist\LumiSetup'
if (Test-Path -LiteralPath (Join-Path $repo 'dist')) {
    Remove-Item -LiteralPath (Join-Path $repo 'dist') -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $dist | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $dist 'lib') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $dist 'share') | Out-Null

Copy-Item -LiteralPath (Join-Path $repo 'src\installer\Install-Lumi.ps1') -Destination (Join-Path $dist 'Install-Lumi.ps1') -Force
Get-ChildItem -LiteralPath (Join-Path $repo 'src\installer\lib') -Filter '*.ps1' | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path (Join-Path $dist 'lib') $_.Name) -Force
}
Get-ChildItem -LiteralPath (Join-Path $repo 'share') -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path (Join-Path $dist 'share') $_.Name) -Force
}

$helperOut = Join-Path $dist 'LumiHelper.exe'
Invoke-Csc -Output $helperOut -Sources @((Join-Path $repo 'src\helper\LumiHelper.cs')) -References @('System.Web.Extensions.dll')

$cmd = Join-Path $dist 'Install Lumi.cmd'
$lines = @(
    '@echo off',
    'cd /d "%~dp0"',
    'wscript.exe //nologo "%~dp0Launch-Lumi.vbs"',
    'exit /b 0',
    ''
)
[System.IO.File]::WriteAllText($cmd, ($lines -join "`r`n"))

$vbs = Join-Path $dist 'Launch-Lumi.vbs'
$vbsLines = @(
    'Set shell = CreateObject("WScript.Shell")',
    'Set fso = CreateObject("Scripting.FileSystemObject")',
    'folder = fso.GetParentFolderName(WScript.ScriptFullName)',
    'folder = Replace(folder, "''", "''''")',
    'command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -Command ""$ErrorActionPreference=''Continue''; Set-Location -LiteralPath ''" & folder & "''; Get-ChildItem -LiteralPath . -Recurse -File | Unblock-File; & ''.\Install-Lumi.ps1''"""',
    'shell.Run command, 0, False',
    ''
)
[System.IO.File]::WriteAllText($vbs, ($vbsLines -join "`r`n"))

$zip = Join-Path $repo 'dist\LumiSetup-win.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($dist, $zip)
Write-Output ('Built ' + $dist)
