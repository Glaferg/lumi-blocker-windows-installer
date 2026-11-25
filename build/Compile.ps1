function Get-CscPath {
    $candidates = @(
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    throw 'The installer could not be built on this computer.'
}

function Invoke-Csc {
    param(
        [string]$Output,
        [string[]]$Sources,
        [string[]]$References,
        [string]$Target = 'exe'
    )
    $csc = Get-CscPath
    $cscArgs = @('/nologo', '/optimize+', ('/target:' + $Target), '/platform:anycpu', ('/utf8output'), ('/out:' + $Output))
    foreach ($reference in @($References)) {
        if ($reference) { $cscArgs += ('/r:' + $reference) }
    }
    foreach ($source in $Sources) { $cscArgs += $source }
    & $csc @cscArgs
    if ($LASTEXITCODE -ne 0) { throw 'compile failed' }
}
