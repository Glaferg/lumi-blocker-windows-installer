function Read-LumiJsonFile {
    param([string]$Path)
    Add-Type -AssemblyName System.Web.Extensions
    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $ser.MaxJsonLength = 1024 * 1024
    $text = [System.IO.File]::ReadAllText($Path)
    return (ConvertTo-LumiSerializable ($ser.DeserializeObject($text)))
}

function ConvertTo-LumiSerializable {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value -is [ValueType]) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $dict = New-Object 'System.Collections.Generic.Dictionary[string,object]'
        foreach ($key in @($Value.Keys)) {
            $dict[[string]$key] = ConvertTo-LumiSerializable $Value[$key]
        }
        return $dict
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $list = New-Object System.Collections.ArrayList
        foreach ($item in $Value) {
            [void]$list.Add((ConvertTo-LumiSerializable $item))
        }
        return $list
    }
    return [string]$Value
}

function Write-LumiJsonFile {
    param(
        $Object,
        [string]$Path
    )
    Add-Type -AssemblyName System.Web.Extensions
    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $ser.MaxJsonLength = 1024 * 1024
    $json = $ser.Serialize((ConvertTo-LumiSerializable $Object))
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $json, $utf8)
}

function Initialize-LumiSettings {
    param(
        [string]$InstallRoot,
        [string]$Model
    )
    $defaultsPath = Join-Path $InstallRoot 'default-settings.json'
    $settingsPath = Join-Path $InstallRoot 'settings.json'
    $fresh = -not (Test-Path -LiteralPath $settingsPath)
    if ($fresh) {
        Copy-Item -LiteralPath $defaultsPath -Destination $settingsPath -Force
    }
    $settings = Read-LumiJsonFile -Path $settingsPath
    $defaults = Read-LumiJsonFile -Path $defaultsPath
    foreach ($key in @($defaults.Keys)) {
        if (-not $settings.ContainsKey($key) -or $null -eq $settings[$key]) {
            $settings[$key] = $defaults[$key]
        }
    }
    if ($fresh -and $Model) { $settings['model'] = $Model }
    Write-LumiJsonFile -Object $settings -Path $settingsPath
    return $settings
}

function Set-LumiSetting {
    param(
        [string]$InstallRoot,
        [string]$Name,
        $Value
    )
    $settingsPath = Join-Path $InstallRoot 'settings.json'
    $settings = Read-LumiJsonFile -Path $settingsPath
    $settings[$Name] = $Value
    Write-LumiJsonFile -Object $settings -Path $settingsPath
}
