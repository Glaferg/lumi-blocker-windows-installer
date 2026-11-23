function Get-LumiShareDir {
    $dir = $PSScriptRoot
    for ($i = 0; $i -lt 6; $i++) {
        $candidate = Join-Path $dir 'share\product.json'
        if (Test-Path -LiteralPath $candidate) {
            return (Join-Path $dir 'share')
        }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    throw 'Lumi could not finish.'
}

function Get-LumiProduct {
    $path = Join-Path (Get-LumiShareDir) 'product.json'
    $raw = [System.IO.File]::ReadAllText($path)
    return ($raw | ConvertFrom-Json)
}

function Get-LumiConsentText {
    $path = Join-Path (Get-LumiShareDir) 'consent.txt'
    return [System.IO.File]::ReadAllText($path).Trim()
}
