function Start-LumiLog {
    param([string]$Path)
    $script:LumiLogPath = $Path
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Write-LumiLog 'log opened'
}

function Write-LumiLog {
    param([string]$Message)
    if (-not $script:LumiLogPath) { return }
    $line = ([DateTime]::UtcNow.ToString('o')) + ' ' + $Message
    Add-Content -LiteralPath $script:LumiLogPath -Value $line -Encoding UTF8
}
