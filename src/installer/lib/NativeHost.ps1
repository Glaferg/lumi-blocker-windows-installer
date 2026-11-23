function Write-LumiNativeManifest {
    param(
        [string]$ManifestPath,
        [string]$HostName,
        [string]$ExePath,
        [string[]]$ExtensionIds
    )
    $dir = Split-Path -Parent $ManifestPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $escapedExe = $ExePath.Replace('\', '\\').Replace('"', '\"')
    $idParts = @()
    foreach ($id in @($ExtensionIds)) {
        if (-not $id) { continue }
        $safe = ([string]$id).Replace('\', '\\').Replace('"', '\"')
        $idParts += ('"' + $safe + '"')
    }
    $idJson = '[' + ($idParts -join ',') + ']'
    $json = @"
{
  "name": "$HostName",
  "description": "Lumi Focus helper",
  "path": "$escapedExe",
  "type": "stdio",
  "allowed_extensions": $idJson
}
"@
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($ManifestPath, $json.Trim() + "`n", $utf8)
}

function Register-LumiNativeHost {
    param(
        [string]$HostName,
        [string]$ManifestPath
    )
    $key = 'HKCU:\Software\Mozilla\NativeMessagingHosts\' + $HostName
    if (-not (Test-Path -LiteralPath $key)) {
        New-Item -Path $key -Force | Out-Null
    }
    Set-Item -LiteralPath $key -Value $ManifestPath
}

function Unregister-LumiNativeHost {
    param([string]$HostName)
    $leaf = 'HKCU:\Software\Mozilla\NativeMessagingHosts\' + $HostName
    if (Test-Path -LiteralPath $leaf) {
        Remove-Item -LiteralPath $leaf -Force
    }
    foreach ($parent in @(
        'HKCU:\Software\Mozilla\NativeMessagingHosts',
        'HKCU:\Software\Mozilla'
    )) {
        if (-not (Test-Path -LiteralPath $parent)) { continue }
        $item = Get-Item -LiteralPath $parent
        if ($item.SubKeyCount -eq 0 -and $item.ValueCount -eq 0) {
            Remove-Item -LiteralPath $parent -Force
        }
    }
}

function Read-ConfiguredExtensionIds {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $json = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json
    $ids = @()
    if ($json.ids) {
        foreach ($id in @($json.ids)) {
            if ($id) { $ids += [string]$id }
        }
    }
    return $ids
}
