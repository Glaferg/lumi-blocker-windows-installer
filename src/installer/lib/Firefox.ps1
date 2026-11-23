function Get-FirefoxClass {
    param(
        [bool]$Found,
        [int]$Major,
        [int]$Minimum
    )
    if (-not $Found) { return 'missing' }
    if ($Major -lt $Minimum) { return 'older' }
    return 'ok'
}

function Get-FirefoxMajorFromFile {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return 0 }
    $info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
    if ($info.FileMajorPart -gt 0) { return [int]$info.FileMajorPart }
    if ($info.ProductMajorPart -gt 0) { return [int]$info.ProductMajorPart }
    return 0
}

function Find-FirefoxExecutable {
    $candidates = New-Object System.Collections.Generic.List[string]
    $regPaths = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe'
    )
    foreach ($regPath in $regPaths) {
        if (Test-Path -LiteralPath $regPath) {
            $item = Get-Item -LiteralPath $regPath
            $value = $item.GetValue('')
            if ($value) { $candidates.Add([string]$value) }
        }
    }
    $pf86 = ${env:ProgramFiles(x86)}
    $paths = @(
        (Join-Path $env:ProgramFiles 'Mozilla Firefox\firefox.exe'),
        (Join-Path $env:LOCALAPPDATA 'Mozilla Firefox\firefox.exe')
    )
    if ($pf86) { $paths += (Join-Path $pf86 'Mozilla Firefox\firefox.exe') }
    foreach ($path in $paths) {
        if ($path) { $candidates.Add($path) }
    }
    foreach ($path in $candidates) {
        if ($path -and (Test-Path -LiteralPath $path)) { return $path }
    }
    return $null
}

function Get-LumiFirefoxStatus {
    param(
        [string]$ExecutablePath,
        [int]$MinimumMajor = 115
    )
    $path = $ExecutablePath
    if (-not $path) { $path = Find-FirefoxExecutable }
    if (-not $path -or -not (Test-Path -LiteralPath $path)) {
        return @{ Status = 'missing'; Major = 0; Path = $path }
    }
    $major = Get-FirefoxMajorFromFile -Path $path
    $status = Get-FirefoxClass -Found $true -Major $major -Minimum $MinimumMajor
    return @{ Status = $status; Major = $major; Path = $path }
}

function Get-LumiExtensionIdsFromProfiles {
    param(
        [string]$ProfileRoot,
        [string]$ExtensionName
    )
    $found = New-Object System.Collections.Generic.List[string]
    if (-not $ProfileRoot -or -not (Test-Path -LiteralPath $ProfileRoot)) { return @() }
    $profileDirs = New-Object System.Collections.Generic.List[string]
    $ini = Join-Path $ProfileRoot 'profiles.ini'
    if (Test-Path -LiteralPath $ini) {
        $relative = $true
        foreach ($line in [System.IO.File]::ReadAllLines($ini)) {
            if ($line -like 'IsRelative=*') {
                $relative = ($line.Substring(11) -eq '1')
            }
            if ($line -like 'Path=*') {
                $rel = $line.Substring(5).Replace('/', '\')
                if ($relative) {
                    $profileDirs.Add((Join-Path $ProfileRoot $rel))
                } else {
                    $profileDirs.Add($rel)
                }
            }
        }
    }
    if ($profileDirs.Count -eq 0) {
        foreach ($dir in (Get-ChildItem -LiteralPath $ProfileRoot -Directory -ErrorAction SilentlyContinue)) {
            $profileDirs.Add($dir.FullName)
        }
    }
    foreach ($dir in $profileDirs) {
        $ext = Join-Path $dir 'extensions.json'
        if (-not (Test-Path -LiteralPath $ext)) { continue }
        try {
            $json = [System.IO.File]::ReadAllText($ext) | ConvertFrom-Json
        } catch {
            continue
        }
        if (-not $json.addons) { continue }
        foreach ($addon in @($json.addons)) {
            $name = ''
            if ($addon.defaultLocale -and $addon.defaultLocale.name) { $name = [string]$addon.defaultLocale.name }
            elseif ($addon.name) { $name = [string]$addon.name }
            if ($name -eq $ExtensionName -and $addon.id) {
                if (-not $found.Contains([string]$addon.id)) { $found.Add([string]$addon.id) }
            }
        }
    }
    return @($found.ToArray())
}
