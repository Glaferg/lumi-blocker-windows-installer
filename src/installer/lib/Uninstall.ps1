function Remove-LumiTree {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    $attempt = 0
    while ($attempt -lt 4) {
        $attempt += 1
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            return $true
        } catch {
            Write-LumiLog 'remove retry'
            Start-Sleep -Milliseconds 200
        }
    }
    return -not (Test-Path -LiteralPath $Path)
}

function Stop-LumiBackend {
    param($ProcessId)
    if (-not $ProcessId) { return }
    $idValue = 0
    if (-not [int]::TryParse([string]$ProcessId, [ref]$idValue)) { return }
    if ($idValue -le 0) { return }
    $alive = Get-Process -Id $idValue -ErrorAction SilentlyContinue
    if (-not $alive) { return }
    Stop-Process -Id $idValue -Force -ErrorAction SilentlyContinue
    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-Process -Id $idValue -ErrorAction SilentlyContinue)) { return }
        Start-Sleep -Milliseconds 100
    }
}

function Test-SafeOllamaDir {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.Length -lt 8) { return $false }
    $leaf = Split-Path -Leaf $full
    if ($leaf -ne 'Ollama') { return $false }
    return $true
}

function Remove-LumiShortcuts {
    $programs = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    foreach ($name in @('Lumi Setup.lnk', 'Remove Lumi.lnk')) {
        $path = Join-Path $programs $name
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
        }
    }
}

function Uninstall-LumiProduct {
    param(
        [string]$InstallRoot,
        [switch]$RemoveOllama,
        [string]$ResultPath,
        $Product
    )
    $messages = Get-LumiMessages -Product $Product
    $warning = ''
    $state = $null
    $statePath = Join-Path $InstallRoot 'install-state.json'
    if (Test-Path -LiteralPath $statePath) {
        $state = Read-LumiJsonFile -Path $statePath
    }
    if ($state -and $state.ContainsKey('backendPid')) {
        Stop-LumiBackend -ProcessId $state['backendPid']
    }
    if ($state -and $state.ContainsKey('originsSaved') -and $state['originsSaved']) {
        $previous = ''
        if ($state.ContainsKey('previousOllamaOrigins') -and $state['previousOllamaOrigins']) {
            $previous = [string]$state['previousOllamaOrigins']
        }
        Set-UserOllamaOrigins -Value $previous
        Write-LumiLog 'origins restored'
    }
    Unregister-LumiNativeHost -HostName $Product.nativeHostName
    Remove-LumiShortcuts
    if ($RemoveOllama -and $state -and $state.ContainsKey('ollamaInstalledByLumi') -and $state['ollamaInstalledByLumi']) {
        $ollamaDir = ''
        if ($state.ContainsKey('ollamaProgramDir')) { $ollamaDir = [string]$state['ollamaProgramDir'] }
        if (Test-SafeOllamaDir -Path $ollamaDir) {
            Remove-LumiTree -Path $ollamaDir | Out-Null
            Write-LumiLog 'ollama folder removed'
        }
    }
    $removed = $true
    if (Test-Path -LiteralPath $InstallRoot) {
        $removed = Remove-LumiTree -Path $InstallRoot
    }
    if (-not $removed) { $warning = $messages.RemoveLocked }
    $result = @{
        ok = [bool]$removed
        action = 'uninstall'
        message = $(if ($removed) { 'Lumi has been removed.' } else { $warning })
        warning = $warning
    }
    if ($ResultPath) {
        Write-LumiJsonFile -Object $result -Path $ResultPath
    }
    if ($removed) { return 0 }
    return 1
}
